defmodule Ambry.Media.Scanner.Tags do
  @moduledoc """
  Embedded metadata read out of an audiobook file — the tags-first half of
  discovery.

  Audiobook tagging is a set of conventions rather than a standard, and the
  two containers spell everything differently, so this normalizes both into
  one struct:

  | Fact | mp3 (ID3v2) | m4b (MP4 atoms) |
  |---|---|---|
  | book title | `TALB` (album) | `©alb` |
  | author(s) | `TPE1`/`TPE2` | `©ART`/`aART` |
  | narrator(s) | `TCOM` (composer) | `©wrt` |
  | series | `TXXX:SERIES`, `MVNM` | freeform `SERIES`, `mvnm` |
  | series number | `TXXX:SERIES-PART`, `MVIN` | freeform, `mvi` |
  | ASIN | `TXXX:ASIN` | `----:com.apple.iTunes:ASIN` |

  The narrator-in-composer convention is what Audible and Libation-style rips
  use, and it's the one genuinely load-bearing mapping here — it's the only
  place a narrator credit appears in a file at all.

  ffprobe surfaces both `TXXX:` frames and MP4 freeform atoms under their
  bare names, which is why no tag library beyond it is needed (the open
  question in the roadmap's 1b). Cover art arrives as an `attached_pic`
  stream and is detected here; pulling the image out is
  `ffmpeg -i <file> -an -c:v copy <out>.jpg` when something wants it.

  ## What this deliberately does not do

  Nothing here is applied to anything. Providers and tags *propose*; the
  operator owns structure (the roadmap's 1c non-goal). The consumer is 1g
  auto-match, which turns these into pre-filled inbox items for confirmation.
  """

  alias Ambry.Media.Scanner.Tags

  defstruct [
    :title,
    :book_title,
    :series,
    :series_number,
    :published,
    :published_format,
    :description,
    :publisher,
    :genre,
    :language,
    :asin,
    authors: [],
    narrators: [],
    has_cover_art: false,
    raw: %{}
  ]

  # Container bookkeeping ffprobe reports as "tags" — never metadata.
  @noise ~w(major_brand minor_version compatible_brands encoder creation_time handler_name
            vendor_id compatible_brand media_type)

  @doc """
  Parses a raw ffprobe tag map into normalized metadata.
  """
  def parse(raw_tags, opts \\ []) when is_map(raw_tags) do
    tags = normalize_keys(raw_tags)

    %Tags{
      title: get(tags, ~w(title)),
      book_title: book_title(tags, opts),
      authors: get_list(tags, ~w(artist album_artist author authors)),
      narrators: get_list(tags, ~w(composer narrator narrators)),
      series: get(tags, ~w(series movement_name mvnm grouping)),
      series_number: get_number(tags, ~w(series-part series_part part movement mvi)),
      description: get(tags, ~w(description comment synopsis ldes desc)),
      publisher: get(tags, ~w(publisher label)),
      genre: get(tags, ~w(genre)),
      language: get(tags, ~w(language)),
      asin: get_asin(tags),
      has_cover_art: Keyword.get(opts, :has_cover_art, false),
      raw: tags
    }
    |> put_published(tags)
  end

  # Which of `album` and `title` holds the book depends on how many files
  # there are, and getting it backwards is expensive: it's the search query.
  #
  # The convention is album = book, title = this file's chapter — true for a
  # folder of mp3s. But a single-file recording has no chapter to name, and
  # measured across a real library `title` was the better book title in 11 of
  # the 12 cases where the two differed ("Interdependency Book 1" vs "The
  # Collapsing Empire"; "01 Electric Angel" vs "Electric Angel"): taggers put
  # series and track numbers in `album`.
  defp book_title(tags, opts) do
    if Keyword.get(opts, :single_file, false) do
      get(tags, ~w(title album))
    else
      get(tags, ~w(album title))
    end
    |> strip_track_number()
  end

  # "01 Electric Angel" — an ordering artifact, never part of the title.
  defp strip_track_number(nil), do: nil

  defp strip_track_number(title) do
    stripped = String.replace(title, ~r/^\d{1,3}(\.\d+)?[-.\s]+(?=\D)/, "")

    if !blank?(stripped), do: stripped
  end

  @doc """
  Whether anything usable was found — an untagged rip parses to an empty
  struct rather than an error.
  """
  def any?(%Tags{} = tags) do
    Enum.any?(
      [tags.title, tags.book_title, tags.series, tags.description, tags.publisher, tags.asin],
      & &1
    ) or tags.authors != [] or tags.narrators != []
  end

  # ffprobe reports keys in whatever case the file used, and prefixes ID3
  # user-defined frames with "TXXX:" — index both away so lookups are boring.
  defp normalize_keys(raw_tags) do
    raw_tags
    |> Enum.flat_map(fn {key, value} ->
      key = key |> to_string() |> String.trim() |> String.downcase()
      key = String.replace_prefix(key, "txxx:", "")

      if key in @noise or blank?(value), do: [], else: [{key, String.trim(value)}]
    end)
    |> Map.new()
  end

  defp get(tags, keys) do
    Enum.find_value(keys, &Map.get(tags, &1))
  end

  # Multi-value tags are a single string with no agreed separator. Splitting
  # can be wrong ("Sanderson, Brandon" is one person), which is fine here:
  # these are proposals, the operator confirms them, and `raw` keeps the
  # original string for a consumer that wants to try a whole-string match
  # first.
  defp get_list(tags, keys) do
    case get(tags, keys) do
      nil ->
        []

      value ->
        value
        |> String.split(~r/\s*[;,&]\s*|\s+(?:and|feat\.?|with)\s+/i)
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))
        |> Enum.uniq()
    end
  end

  defp get_number(tags, keys) do
    with value when is_binary(value) <- get(tags, keys),
         [number] <- Regex.run(~r/\d+(?:\.\d+)?/, value),
         {decimal, ""} <- Decimal.parse(number) do
      decimal
    else
      _no_number -> nil
    end
  end

  # ASINs are 10-character Amazon identifiers; anything else in the field is
  # somebody else's convention and not worth guessing at.
  defp get_asin(tags) do
    with value when is_binary(value) <- get(tags, ~w(asin audible_asin amazon_asin)),
         value = String.upcase(value),
         true <- Regex.match?(~r/^[A-Z0-9]{10}$/, value) do
      value
    else
      _not_an_asin -> nil
    end
  end

  # Reuses the same granularity the rest of the app already models on
  # `published_format`: a tag saying "2010" must not become "Jan 1st, 2010".
  defp put_published(%Tags{} = tags, raw) do
    case get(raw, ~w(date year originaldate original_year)) do
      nil ->
        tags

      value ->
        case parse_date(value) do
          {:ok, date, format} -> %{tags | published: date, published_format: format}
          :error -> tags
        end
    end
  end

  defp parse_date(value) do
    case Regex.run(~r/^(\d{4})(?:-(\d{2}))?(?:-(\d{2}))?/, String.trim(value)) do
      [_match, year] -> build_date(year, "1", "1", :year)
      [_match, year, month] -> build_date(year, month, "1", :year_month)
      [_match, year, month, day] -> build_date(year, month, day, :full)
      _unparseable -> :error
    end
  end

  defp build_date(year, month, day, format) do
    case Date.new(String.to_integer(year), String.to_integer(month), String.to_integer(day)) do
      {:ok, date} -> {:ok, date, format}
      {:error, _reason} -> :error
    end
  end

  defp blank?(value), do: !is_binary(value) or String.trim(value) == ""
end
