defmodule Ambry.Library.NamingTemplate do
  @moduledoc """
  Where a managed recording's files live inside a library root.

  The template describes the *folder*; the file inside it is named after the
  work. So the default

      {author}/{series}/{series_book_number} - {title} ({year})

  produces

      Brandon Sanderson/The Stormlight Archive/1 - The Way of Kings (2010)/
        The Way of Kings.m4b

  This is a pure renderer over a map of already-resolved values — deciding
  *which* author is "the" author is domain knowledge that belongs with books,
  not with the filesystem. See `Ambry.Books.naming_values/2`.

  ## Empty segments collapse

  A standalone book has no series, and a book can be in a series without a
  number. Rather than producing `Author//Title` or a stray leading `- `, a
  segment whose tokens all resolve to nothing is dropped entirely, and a
  partially-empty segment loses the punctuation that was only there to join
  the missing part. Otherwise every standalone book in the library would sit
  in a folder whose name starts with a dash.
  """

  @default "{author}/{series}/{series_book_number} - {title} ({year})"

  @tokens ~w(author series series_book_number title year narrator)

  # Separators and brackets are stripped rather than substituted: a title
  # containing a slash must not silently become two directories, and a NUL or
  # a control character has no business in a filename at all. Everything else
  # — apostrophes, commas, ampersands, unicode — is left alone, because
  # mangling "Gwendy's Button Box" helps nobody.
  @unsafe ~r/[\/\\:\*\?"<>\|\x00-\x1f]/

  # Most filesystems cap a single name at 255 bytes. Truncating on a byte
  # boundary can split a multi-byte character, so it's done on graphemes.
  @max_segment_bytes 255

  def default_template, do: @default
  def tokens, do: @tokens

  @doc """
  The folder path for a recording, relative to its library root.

  Returns `{:error, :no_title}` rather than inventing a name — a folder called
  "Unknown" is worse than a refusal that says what's missing.
  """
  def render(template \\ @default, values) do
    values = stringify(values)

    if blank?(values["title"]) do
      {:error, :no_title}
    else
      {:ok,
       template
       |> String.split("/")
       |> Enum.map(&segment(&1, values))
       |> Enum.reject(&(&1 == ""))
       |> Path.join()}
    end
  end

  @doc """
  The filename for a recording's file, keeping the source's extension.

  See `filenames/3` — `recording` describes which recording this is.
  """
  def filename(values, source_path, recording \\ %{}) do
    with {:ok, [name]} <- filenames(values, [source_path], recording), do: {:ok, name}
  end

  @doc """
  The names for every file of a recording, relative to its book folder.

  A single-file recording is one name sitting directly in the folder, exactly
  as before. A multi-file one gets a **subfolder of its own**, with its files
  renamed to a zero-padded index:

      1 - Words of Radiance (2014)/
        Words of Radiance/
          Words of Radiance - 001.mp3
          Words of Radiance - 002.mp3

  Two things make the subfolder non-negotiable. Forty files loose in the book
  folder would sit alongside the *other* recordings of that book — the folder
  is shared by every part of a set and by a second reading of the same work —
  and pruning or deleting one of them could then no longer tell whose files
  were whose. And the index has to be rendered rather than inherited: play
  order is the order these names are generated in, so it must be legible on
  disk instead of depending on how the release happened to name things.

  Renaming loses nothing that isn't already captured. Chapter titles are read
  off the source filenames at import (the roadmap's 1h), and a hardlinked
  source keeps its own name regardless — the library copy is a second name for
  the same bytes, not a replacement.

  ## The recording descriptor

  `recording` says which recording of the work this is, and both of its keys
  are appended to the **name stem** — the thing that has to be unique inside a
  book folder, being the filename for a single-file recording and the
  subfolder name for a multi-file one:

    * `:part` — `%{number: n, total: t, word: w}` for a member of a part set,
      rendering " - Part 2 of 3" in the group's own wording. Meaningful, and
      what a human reads.
    * `:token` — the recording's own short identifier, rendering " [7bKq]".
      Meaningless, and what makes the name *guaranteed* unique.

  ### Why the token is always there

  A book folder is shared on purpose: by every part of a set, and by every
  recording of the same work. Two readings of one book published the same year
  therefore rendered to one identical path, and placement refused —
  `{narrator}` in the template was the documented workaround, which taxes
  every book in the library for a problem a handful have.

  The token could have been added only on collision, and deliberately isn't.
  That would make one recording's correct name depend on the *existence of
  another record*, so the nightly organize would have to re-derive that
  relationship every time it ran — and a re-derivation that quietly un-answers
  a settled question is this codebase's most-repeated bug. With the token
  always present the path is a pure function of the record, organize stays a
  rename-to-computed-path, and `{:destination_exists, _}` stops being an
  expected operator-facing outcome and becomes what it should be: a sign that
  two records claim one path, which is a bug.

  Nothing *inside* a multi-file recording's own folder repeats the token — the
  ` - 001` index already makes those unique, and the folder carries the
  guarantee.
  """
  def filenames(values, source_paths, recording \\ %{})

  def filenames(_values, [], _recording), do: {:ok, []}

  def filenames(values, source_paths, recording) do
    values = stringify(values)

    case sanitize(to_string(values["title"] || "")) do
      "" ->
        {:error, :no_title}

      name ->
        titled = name <> part_suffix(recording[:part])
        {:ok, build_filenames(titled <> token_suffix(recording[:token]), titled, source_paths)}
    end
  end

  # `stem` is what must be unique inside the book folder; `titled` is the same
  # name without the token, for the files inside a recording's own folder —
  # where the index is already all the uniqueness there is to need.
  defp build_filenames(stem, _titled, [source_path]), do: [stem <> extname(source_path)]

  defp build_filenames(stem, titled, source_paths) do
    width = index_width(length(source_paths))

    source_paths
    |> Enum.with_index(1)
    |> Enum.map(fn {source_path, index} ->
      padded = index |> to_string() |> String.pad_leading(width, "0")
      Path.join(stem, "#{titled} - #{padded}#{extname(source_path)}")
    end)
  end

  # Bracketed, per the convention every media tool already uses for a token
  # that isn't part of the title, so nothing mistakes it for one.
  defp token_suffix(nil), do: ""
  defp token_suffix(""), do: ""
  defp token_suffix(token), do: " [#{token}]"

  # Three digits unless there are genuinely more files than that, so a
  # forty-file book reads 001..040 and never gets re-padded by a later
  # re-organize.
  defp index_width(count), do: max(3, count |> to_string() |> String.length())

  defp extname(source_path), do: source_path |> Path.extname() |> String.downcase()

  defp part_suffix(nil), do: ""

  defp part_suffix(%{number: number} = part) do
    word = String.capitalize(part[:word] || "part")

    case part[:total] do
      nil -> " - #{word} #{number}"
      total -> " - #{word} #{number} of #{total}"
    end
  end

  @doc """
  Checks a template without needing anything to render it against.
  """
  def validate(template) do
    cond do
      blank?(template) -> {:error, :blank}
      String.starts_with?(template, "/") -> {:error, :absolute}
      String.contains?(template, "..") -> {:error, :traversal}
      unknown = unknown_token(template) -> {:error, {:unknown_token, unknown}}
      not String.contains?(template, "{title}") -> {:error, :no_title_token}
      true -> :ok
    end
  end

  defp stringify(values) do
    Map.new(values, fn {key, value} -> {to_string(key), value} end)
  end

  defp unknown_token(template) do
    ~r/\{([^}]*)\}/
    |> Regex.scan(template, capture: :all_but_first)
    |> List.flatten()
    |> Enum.find(&(&1 not in @tokens))
  end

  # One path segment. If every token in it is empty the segment disappears;
  # if only some are, the literal text that joined them goes too, so a
  # missing series number doesn't leave "- The Way of Kings".
  defp segment(segment, values) do
    tokens = ~r/\{([^}]*)\}/ |> Regex.scan(segment, capture: :all_but_first) |> List.flatten()

    cond do
      tokens == [] -> sanitize(segment)
      Enum.all?(tokens, &blank?(values[&1])) -> ""
      true -> segment |> drop_empty_token_phrases(values) |> replace_tokens(values) |> sanitize()
    end
  end

  # Removes an empty token together with the punctuation and spacing that
  # only existed to attach it: " - {series_book_number}" or "({year})".
  defp drop_empty_token_phrases(segment, values) do
    Enum.reduce(@tokens, segment, fn token, segment ->
      if blank?(values[token]) do
        segment
        |> String.replace(~r/\s*[-–—:]\s*\{#{token}\}/, "")
        |> String.replace(~r/\s*[\(\[]\s*\{#{token}\}\s*[\)\]]/, "")
        |> String.replace(~r/\{#{token}\}\s*[-–—:]\s*/, "")
        |> String.replace("{#{token}}", "")
      else
        segment
      end
    end)
  end

  defp replace_tokens(segment, values) do
    Enum.reduce(@tokens, segment, fn token, segment ->
      String.replace(segment, "{#{token}}", to_string(values[token] || ""))
    end)
  end

  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank?(_value), do: false

  defp sanitize(segment) do
    segment
    |> String.replace(@unsafe, "")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
    # A trailing dot or space is legal on Linux and silently dropped by
    # Windows and SMB, which is where these files are usually read from.
    |> String.trim_trailing(".")
    |> String.trim()
    |> truncate()
  end

  defp truncate(segment) when byte_size(segment) <= @max_segment_bytes, do: segment

  defp truncate(segment) do
    segment
    |> String.graphemes()
    |> Enum.reduce_while({[], 0}, fn grapheme, {acc, size} ->
      size = size + byte_size(grapheme)

      if size > @max_segment_bytes,
        do: {:halt, {acc, size}},
        else: {:cont, {[grapheme | acc], size}}
    end)
    |> elem(0)
    |> Enum.reverse()
    |> Enum.join()
    |> String.trim()
  end
end
