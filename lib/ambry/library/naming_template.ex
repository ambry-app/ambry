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
  """
  def filename(values, source_path) do
    values = stringify(values)

    case sanitize(to_string(values["title"] || "")) do
      "" -> {:error, :no_title}
      name -> {:ok, name <> String.downcase(Path.extname(source_path))}
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
