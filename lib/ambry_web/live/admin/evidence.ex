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

  alias Ambry.Metadata.Provider

  defstruct fields: %{},
            searched?: false,
            running?: false,
            records: [],
            outcomes: [],
            used: MapSet.new()

  @type t :: %__MODULE__{}

  @doc """
  A fresh panel, seeded with the search fields the record itself suggests —
  the same string-keyed `%{"title" => _, "author" => _, "narrator" => _}`
  shape every search-again form submits (`Provider.Query.from_fields/1`).
  """
  def new(fields) when is_map(fields), do: %__MODULE__{fields: stringify(fields)}

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
  Folds a fan-out's `{found, outcomes}` into the panel.

  `found` is `Ambry.Metadata.Search.books/2` shape — `{registry_entry,
  books}` pairs. New records join the list; records already held keep their
  place and their tick. Outcomes replace per provider, so "couldn't be
  reached" stops saying that once it has been reached.
  """
  def absorb(%__MODULE__{} = evidence, {found, outcomes}) do
    fresh = Enum.flat_map(found, fn {entry, books} -> Enum.map(books, &record(&1, entry)) end)
    absorb_records(evidence, fresh, outcomes)
  end

  @doc """
  Folds a person fan-out's `{matches, outcomes}` into the panel —
  `Ambry.Metadata.Search.people/2` shape, flat matches across providers.
  """
  def absorb_people(%__MODULE__{} = evidence, {matches, outcomes}) do
    absorb_records(evidence, Enum.map(matches, &person_record/1), outcomes)
  end

  defp absorb_records(evidence, fresh, outcomes) do
    known = MapSet.new(evidence.records, &ref/1)
    added = Enum.reject(fresh, &MapSet.member?(known, ref(&1)))

    fresh_ids = MapSet.new(outcomes, & &1["id"])
    kept = Enum.reject(evidence.outcomes, &MapSet.member?(fresh_ids, &1["id"]))

    %{
      evidence
      | searched?: true,
        running?: false,
        records: evidence.records ++ added,
        outcomes: kept ++ outcomes
    }
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
  params directly; `:authors`, `:narrators` and `:series` propose entities
  and the LiveView owns resolving them into rows.
  """
  def proposals(%__MODULE__{} = evidence, field) do
    evidence
    |> used_records()
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
      format = record["published_format"] || "full"
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
  defp field_values(record, :image) do
    urls = List.wrap(record["images"] || present(record["cover_url"]))

    for url <- urls do
      record
      |> value(url, url, %{"image_type" => "url_import", "image_import_url" => url})
      |> Map.put(:image, url)
    end
  end

  defp field_values(record, :authors) do
    for name <- List.wrap(record["authors"]) do
      value(record, String.downcase(name), name, %{"name" => name})
    end
  end

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

  defp value(record, group_key, display, params) do
    %{
      group: group_key,
      display: display,
      params: params,
      source: record["source"],
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
        image: first[:image],
        providers: holders |> Enum.map(& &1.provider) |> Enum.uniq()
      }
    end)
    |> Enum.sort_by(& &1.display)
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

  # ── normalization: provider structs → the record maps the evidence UI
  #    renders (the same vocabulary inbox records use, minus the inbox's
  #    hint-scoring — an edit form's search is the operator's own query) ──

  defp record(%Provider.Book{} = book, entry) do
    %{
      "source" => "provider:#{entry.id}",
      "provider_name" => entry.display_name,
      "id" => to_string(book.id),
      "asin" => book.asin,
      "title" => book.title,
      "authors" => Enum.map(book.authors || [], & &1.name),
      "narrators" => Enum.map(book.narrators || [], & &1.name),
      "series" => series_refs(book.series),
      "published" =>
        book.published && book.published.date && Date.to_iso8601(book.published.date),
      "published_format" => book.published && to_string(book.published.display_format),
      "publisher" => book.publisher,
      "cover_url" => book.cover_url,
      "description" => book.description
    }
  end

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

  defp series_refs(series) do
    for entry <- List.wrap(series), is_binary(entry.name) do
      %{"name" => entry.name, "number" => number_string(entry.number)}
    end
  end

  defp number_string(nil), do: nil
  defp number_string(%Decimal{} = number), do: Decimal.to_string(number, :normal)

  defp number_string(number) do
    case String.trim(to_string(number)) do
      "" -> nil
      trimmed -> trimmed
    end
  end
end
