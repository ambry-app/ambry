defmodule Ambry.Library.NamingTemplate do
  @moduledoc """
  Where a managed recording's files live inside a library root.

  The template describes the *folder*; the file inside it is named after the
  work. So the default

      {author}/{series}/{series_book_number} - {title} ({year})

  produces

      Brandon Sanderson/The Stormlight Archive/1 - The Way of Kings (2010)/
        The Way of Kings.m4b

  A pure renderer over already-resolved values: deciding *which* author is
  "the" author belongs with books (`Ambry.Books.naming_values/2`).

  Empty segments collapse. A segment whose tokens all resolve to nothing is
  dropped, and a partially-empty one loses the punctuation that was only there
  to join the missing part, so a standalone book never sits in `Author//Title`
  or a folder starting with a dash.
  """

  @default "{author}/{series}/{series_book_number} - {title} ({year})"

  @tokens ~w(author series series_book_number title year narrator)

  # Stripped rather than substituted: a title containing a slash must not
  # become two directories. Everything else is left alone.
  @unsafe ~r/[\/\\:\*\?"<>\|\x00-\x1f]/

  # Most filesystems cap a single name at 255 bytes. Truncating on a byte
  # boundary can split a multi-byte character, so it's done on graphemes.
  @max_segment_bytes 255

  def default_template, do: @default
  def tokens, do: @tokens

  @doc """
  The folder path for a recording, relative to its library root.

  Returns `{:error, :no_title}` rather than inventing a name.
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
  The filename for a recording's file, keeping the source's extension (except
  that audio MPEG-4 is named `.m4b` whatever it arrived as — see `extname/1`).

  See `filenames/3` — `recording` describes which recording this is.
  """
  def filename(values, source_path, recording \\ %{}) do
    with {:ok, [name]} <- filenames(values, [source_path], recording), do: {:ok, name}
  end

  @doc """
  The names for every file of a recording, relative to its book folder.

  A single-file recording is one name sitting directly in the folder. A
  multi-file one gets a **subfolder of its own**, with its files renamed to a
  zero-padded index:

      1 - Words of Radiance (2014)/
        Words of Radiance/
          Words of Radiance - 001.mp3
          Words of Radiance - 002.mp3

  The book folder is shared by every part of a set and by every recording of
  the same work, so without the subfolder forty loose files could not be told
  from another recording's. The index is rendered rather than inherited,
  because play order must be legible on disk.

  Renaming loses nothing: chapter titles are read off the source filenames at
  import, and a hardlinked source keeps its own name.

  ## The recording descriptor

  Both keys of `recording` are appended to the **name stem** — the filename
  for a single-file recording, the subfolder name for a multi-file one:

    * `:part` — `%{number: n, total: t, word: w}`, rendering " - Part 2 of 3"
      in the set's own wording. What a human reads.
    * `:token` — the recording's short identifier, rendering " [7bKq]". What
      makes the name *guaranteed* unique.

  **The token is always there**, never added only on collision: a
  conditional token makes one recording's correct name depend on the
  existence of another record. Always present, the path is a pure function of
  the record, and `{:destination_exists, _}` means two records claim one
  path.

  Nothing *inside* a multi-file recording's folder repeats the token; the
  ` - 001` index already makes those unique.
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

  # `stem` is what must be unique inside the book folder; `titled` is the
  # same without the token, for files inside a recording's own folder.
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

  # Three digits unless there are genuinely more files, so a re-organize
  # never re-pads.
  defp index_width(count), do: max(3, count |> to_string() |> String.length())

  # `.mp4`, `.m4a` and `.m4b` are the same container, and audiobook players
  # key their behaviour off `.m4b`. Nothing about the bytes changes. Every
  # other format keeps its extension: an mp3 is not an m4b.
  defp extname(source_path) do
    source_path
    |> Path.extname()
    |> String.downcase()
    |> case do
      ext when ext in [".mp4", ".m4a"] -> ".m4b"
      ext -> ext
    end
  end

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

  # One path segment. All tokens empty and the segment disappears; some empty
  # and the literal text that joined them goes too.
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
