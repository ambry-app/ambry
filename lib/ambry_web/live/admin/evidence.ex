defmodule AmbryWeb.Admin.Evidence do
  @moduledoc """
  The edit forms' evidence panel: what the databases said, which records the
  operator ticked, and what the ticked records propose for each field.

  This is the import form's model carried onto records that already exist —
  one search fans out to every capable provider (`Ambry.Metadata.Search`),
  results are tickable evidence, and ticked records grow "Proposed" chips
  under the fields they can fill. What differs from the inbox is the
  lifetime: an inbox item's evidence is part of a staged draft that ends in
  one import, while an edit form lives forever, so this evidence is
  **session state** — held in socket assigns, never persisted. The durable
  trace of an accepted proposal is the field's provenance entry
  (`Ambry.Provenance`), written on save via `AmbryWeb.Admin.ProvenanceHints`.

  Nothing here talks to a provider; the LiveView runs the fan-out in a
  `start_async` and feeds the results through `absorb/2`. Records follow the
  same law as inbox evidence: **added, never replaced**, so a re-search
  cannot un-tick what the operator chose.
  """
  # What a tags record can propose — if it carries none of these there is
  # nothing to offer and no row worth rendering.
  import AmbryWeb.Admin.Decisions, only: [source_words: 1]

  alias Ambry.Inbox
  alias Ambry.Media.Scanner.Tags

  @tags_fields ~w(title authors narrators published publisher description series asin
                  embedded_cover)

  defstruct fields: %{},
            searched?: false,
            running?: false,
            records: [],
            outcomes: [],
            used: MapSet.new(),
            known: %{},
            tags: nil

  @type t :: %__MODULE__{}

  @doc """
  A fresh panel, seeded with the search fields the record itself suggests —
  the same string-keyed `%{"title" => _, "author" => _, "narrator" => _}`
  shape every search-again form submits (`Provider.Query.from_fields/1`).
  """
  def new(fields, opts \\ []) when is_map(fields) do
    %__MODULE__{fields: stringify(fields), known: Keyword.get(opts, :known, %{})}
  end

  @doc """
  The record refs a persisted record's provenance points back at — ref →
  the fields that record filled. Built from the `"record"` keys accepted
  proposals and imports write; it's what lets a later search *recognize*
  the record that filled the title, pre-tick it, and say so.
  """
  def known_from(%{field_provenance: prov}) when is_map(prov) do
    Enum.reduce(prov, %{}, fn {field, entry}, acc ->
      case entry do
        %{"source" => "provider:" <> _ = source, "record" => record} ->
          Map.update(acc, {source, to_string(record)}, [field], &(&1 ++ [field]))

        _no_ref ->
          acc
      end
    end)
  end

  def known_from(_record), do: %{}

  @doc "Marks the panel as waiting on a fan-out for `fields`."
  def begin(%__MODULE__{} = evidence, fields) do
    %{evidence | fields: stringify(fields), running?: true}
  end

  defp stringify(fields) do
    for {key, value} <- fields, value not in [nil, ""], into: %{} do
      {to_string(key), to_string(value)}
    end
  end

  @doc """
  Folds a fan-out's `{records, outcomes}` into the panel — records already
  normalized and scored (`Ambry.Inbox.score_records/3`), so the panel ranks
  and meters them exactly the way matching does. New records join the list;
  records already held keep their place and their tick. Outcomes replace
  per provider, so "couldn't be reached" stops saying that once it has
  been reached.
  """
  def absorb(%__MODULE__{} = evidence, {records, outcomes}) when is_list(records) do
    absorb_records(evidence, records, outcomes)
  end

  @doc """
  Folds a person fan-out's `{matches, outcomes}` into the panel —
  `Ambry.Metadata.Search.people/2` shape, flat matches across providers.

  `about: name` ticks the arrivals that are **about that human** — person
  search is recall-first, so a search for one narrator returns everybody who
  shares a name token with them, and only the ones spelling the same name are
  evidence about this person. This is what an import does: `Draft.Seed` uses
  every name-matching candidate as a source without being asked, which is why
  an imported person arrives with a face and a biography and one credited on
  an edit form arrived empty (operator, 2026-08-21).
  """
  def absorb_people(%__MODULE__{} = evidence, {matches, outcomes}, opts \\ []) do
    absorb_records(evidence, Enum.map(matches, &person_record/1), outcomes, about(opts[:about]))
  end

  # Matching's own rule for "one human, two spellings" — initials,
  # punctuation and accents fold (`Ambry.Inbox.person_key/1`).
  defp about(nil), do: fn _record -> false end

  defp about(name) do
    key = Inbox.person_key(name)
    fn record -> is_binary(record["name"]) and Inbox.person_key(record["name"]) == key end
  end

  defp absorb_records(evidence, fresh, outcomes, about \\ fn _record -> false end) do
    held = MapSet.new(evidence.records, &ref/1)
    added = Enum.reject(fresh, &MapSet.member?(held, ref(&1)))

    fresh_ids = MapSet.new(outcomes, & &1["id"])
    kept = Enum.reject(evidence.outcomes, &MapSet.member?(fresh_ids, &1["id"]))

    # A record this record's own provenance points back at arrives ticked —
    # it filled fields here once, so it counts until somebody says otherwise
    # — and so does one that is plainly about the human being asked about.
    # Only NEWLY arrived records auto-tick: re-searching must never re-tick
    # what the operator unticked.
    recognized =
      for record <- added,
          Map.has_key?(evidence.known, ref(record)) or about.(record),
          do: ref(record)

    %{
      evidence
      | searched?: true,
        running?: false,
        records: Enum.sort_by(evidence.records ++ added, &(&1["score"] || 0.0), :desc),
        outcomes: kept ++ outcomes,
        used: Enum.into(recognized, evidence.used)
    }
  end

  @doc """
  Holds the recording's own file tags as a source of proposals.

  The file is evidence, and for a recording imported before the inbox existed
  it is the only evidence that came with it: a narrator in the composer tag, a
  publisher, a date, sometimes a description. The inbox has proposed from tags
  since it existed, and after import there was no way back to a value the
  operator skipped — this is that way back.

  **Not a record.** A record is a claim about a book that might be this one,
  which is why the panel lists them for ticking; the file is this recording,
  so there is nothing to identify and nothing to tick. It proposes the way the
  import form's tag candidates propose — as chips under the fields, labelled
  with where they came from — and the record list stays what it is, a list of
  what the databases said.
  """
  def absorb_tags(%__MODULE__{} = evidence, %Tags{} = tags, opts \\ []) do
    %{evidence | tags: evidence.tags || tags_record(tags, opts)}
  end

  @doc """
  Whether anything can propose: a ticked record, or the file's own tags.

  The gate for rendering chips at all, and deliberately not `any_used?/1` —
  tags propose without being ticked.
  """
  def proposing?(%__MODULE__{} = evidence), do: any_used?(evidence) or evidence.tags != nil

  # The cover is the one thing here that isn't a tag: art is a stream in the
  # container, so the record carries where it can be *seen* rather than a URL
  # to fetch, and accepting it extracts at save time the way an import does.
  # The caller supplies that address, which keeps routes out of this module.
  #
  # "the file's tags" rather than a provider's display name, because that is
  # what the import form calls it (`source_words/1`), and a chip that says one
  # thing here and another there is two vocabularies for one fact.
  defp tags_record(%Tags{} = tags, opts) do
    map = Tags.to_map(tags)

    record = %{
      "source" => "tags",
      "provider_name" => source_words("tags"),
      "id" => "file",
      "title" => map["book_title"],
      "authors" => map["authors"],
      "narrators" => map["narrators"],
      "published" => map["published"],
      "published_format" => map["published_format"],
      "publisher" => map["publisher"],
      "description" => map["description"],
      "series" => tags_series(map),
      "asin" => map["asin"],
      "embedded_cover" => map["has_cover_art"] && opts[:embedded_cover_src]
    }

    if Enum.any?(@tags_fields, &(record[&1] not in [nil, "", []])), do: record
  end

  defp tags_series(%{"series" => name} = map) when is_binary(name) do
    [%{"name" => name, "number" => map["series_number"]}]
  end

  defp tags_series(_no_series), do: []

  @doc """
  What a record already gave this library record, as a short note for its
  row — `"filled title · published"` — or nil for a record provenance never
  pointed at.
  """
  def note(%__MODULE__{} = evidence, record) do
    case evidence.known[ref(record)] do
      nil -> nil
      fields -> "filled " <> (fields |> Enum.sort() |> Enum.map_join(" · ", &field_words/1))
    end
  end

  defp field_words(field) do
    field |> to_string() |> String.replace("_", " ") |> String.replace(" path", "")
  end

  @doc "The stable identity of a record across re-searches."
  def ref(record), do: {record["source"], to_string(record["id"])}

  @doc "Ticks or unticks one record."
  def toggle(%__MODULE__{} = evidence, source, id) do
    ref = {source, to_string(id)}

    used =
      if MapSet.member?(evidence.used, ref),
        do: MapSet.delete(evidence.used, ref),
        else: MapSet.put(evidence.used, ref)

    %{evidence | used: used}
  end

  @doc """
  Unticks everything — the panel's answer to "none of these describes them".
  """
  def use_none(%__MODULE__{} = evidence), do: %{evidence | used: MapSet.new()}

  @doc "Whether a record is ticked."
  def used?(%__MODULE__{} = evidence, record), do: MapSet.member?(evidence.used, ref(record))

  @doc "The ticked records, in evidence order."
  def used_records(%__MODULE__{} = evidence),
    do: Enum.filter(evidence.records, &used?(evidence, &1))

  @doc "Whether anything is ticked — the gate for showing proposal rows."
  def any_used?(%__MODULE__{} = evidence), do: MapSet.size(evidence.used) > 0

  @doc """
  What the ticked records propose for one field.

  Proposals are grouped by value, in evidence order, each carrying: `key` (a
  stable digest, the chip's `phx-value`), `display` (the chip text),
  `params` (what accepting merges into the form), `source` (the provenance
  source recorded — the first provider that proposed it), and `providers`
  (every display name that agrees — the chip's source tag).

  The field kinds mirror what provider records can know. Scalars merge
  params directly; `:authors` and `:series` propose entities and the LiveView
  owns resolving them into rows.
  """
  def proposals(%__MODULE__{} = evidence, field) do
    # Ticked records first: when a provider and the file agree on a value they
    # become one chip, and the first holder is the source it records.
    (used_records(evidence) ++ List.wrap(evidence.tags))
    |> Enum.flat_map(&field_values(&1, field))
    |> group()
  end

  @doc "Finds one proposal by field and chip key."
  def find_proposal(%__MODULE__{} = evidence, field, key) do
    Enum.find(proposals(evidence, field), &(&1.key == key))
  end

  # ── what one record proposes for one field ─────────────────────────────

  defp field_values(record, :title) do
    for value <- present(record["title"]) do
      value(record, value, truncate(value), %{"title" => value})
    end
  end

  defp field_values(record, :name) do
    for value <- present(record["name"]) do
      value(record, value, truncate(value), %{"name" => value})
    end
  end

  defp field_values(record, :published) do
    for date <- present(record["published"]) do
      format = Ambry.Inbox.Draft.Candidate.date_format(date, record["published_format"] || "full")
      display = if format == "full", do: date, else: "#{date} (#{precision_words(format)})"
      value(record, {date, format}, display, %{"published" => date, "published_format" => format})
    end
  end

  defp field_values(record, :publisher) do
    for value <- present(record["publisher"]) do
      value(record, value, value, %{"publisher" => value})
    end
  end

  defp field_values(record, :description) do
    for value <- present(record["description"]) do
      value(record, value, truncate(value), %{"description" => value})
    end
  end

  # Accepting a cover routes through the forms' existing URL-import machinery
  # (`image_type`/`image_import_url`), which downloads at submit time —
  # ProvenanceHints already knows this pair maps to `image_path`.
  #
  # Clearing `image_path` is part of accepting, and it is what makes the
  # choice take effect rather than merely look accepted. The forms render the
  # URL input — the only control that carries the chosen URL back on submit —
  # in the branch for a record with *no* image. So a cover chosen against an
  # existing one marked its chip chosen, wrote a provenance hint, and then
  # posted nothing: the operator had to delete the old cover first and make
  # the same decision twice. Picking a cover is replacing the cover.
  defp field_values(record, :image) do
    urls = List.wrap(record["images"] || present(record["cover_url"]))

    embedded_cover(record) ++
      for url <- urls do
        record
        |> value(url, url, %{
          "image_type" => "url_import",
          "image_import_url" => url,
          "image_path" => ""
        })
        |> Map.put(:image, url)
      end
  end

  defp field_values(record, :authors) do
    for name <- List.wrap(record["authors"]) do
      value(record, String.downcase(name), name, %{"name" => name})
    end
  end

  # The record's narrators, which are people. A recording's whole identity
  # can turn on them — two readings of one book differ by nothing else — and
  # they were the one field a ticked record could not fill.
  defp field_values(record, :narrators) do
    for name <- List.wrap(record["narrators"]) do
      value(record, String.downcase(name), name, %{"name" => name})
    end
  end

  defp field_values(record, :series) do
    for %{"name" => name} = series <- List.wrap(record["series"]) do
      number = series["number"]
      display = if number, do: "#{name} ##{number}", else: name

      value(record, String.downcase(name), display, %{
        "name" => name,
        "number" => number
      })
    end
  end

  # The file's own art, which no URL can name: the chip previews it through
  # the address the caller gave, and accepting it means "extract this on
  # save" rather than "download that". Labelled as the import form labels
  # it, because it is the same decision about the same picture.
  defp embedded_cover(%{"embedded_cover" => src}) when is_binary(src) do
    [
      %{"source" => "embedded", "provider_name" => "Embedded in the file", "id" => "cover"}
      |> value(:embedded, "Embedded in the file", %{
        "image_type" => "embedded",
        "image_path" => ""
      })
      |> Map.put(:image, src)
    ]
  end

  defp embedded_cover(_no_art), do: []

  defp value(record, group_key, display, params) do
    %{
      group: group_key,
      display: display,
      params: params,
      source: record["source"],
      record: record["id"] && to_string(record["id"]),
      provider: record["provider_name"] || record["source"]
    }
  end

  defp present(value) when is_binary(value) do
    case String.trim(value) do
      "" -> []
      trimmed -> [trimmed]
    end
  end

  defp present(_value), do: []

  # One chip per distinct value; every provider that agrees joins its tag.
  defp group(values) do
    values
    |> Enum.group_by(& &1.group)
    |> Map.values()
    |> Enum.map(fn [first | _rest] = holders ->
      %{
        key: digest(first.group),
        display: first.display,
        params: first.params,
        source: first.source,
        record: first[:record],
        image: first[:image],
        providers: holders |> Enum.map(& &1.provider) |> Enum.uniq()
      }
    end)
    # Alphabetical, except the file's own art, which goes last — the import
    # form offers a cover that way round (`from_records(...) ++ [embedded]`)
    # and one order in two places is one thing to learn.
    |> Enum.sort_by(&{&1.source == "embedded", &1.display})
  end

  defp digest(term) do
    term
    |> :erlang.term_to_binary()
    |> then(&:erlang.md5/1)
    |> Base.encode16(case: :lower)
    |> binary_part(0, 12)
  end

  defp truncate(value) when byte_size(value) > 60, do: String.slice(value, 0, 57) <> "…"
  defp truncate(value), do: value

  defp precision_words("year"), do: "year only"
  defp precision_words("year_month"), do: "year & month"
  defp precision_words(other), do: other

  # ── normalization: person matches → the record maps the evidence UI
  #    renders (books arrive pre-normalized and pre-scored from
  #    `Ambry.Inbox.score_records/3`) ──

  defp person_record(match) do
    %{
      "source" => "provider:#{match.provider_id}",
      "provider_name" => match.provider_name,
      "id" => to_string(match.id),
      "name" => match.name,
      "description" => match.description,
      "note" => match.note,
      "images" => match.images
    }
  end
end
