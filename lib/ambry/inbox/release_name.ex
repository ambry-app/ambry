defmodule Ambry.Inbox.ReleaseName do
  @moduledoc """
  Reads what it can out of a release folder or file name.

  This is the fallback for candidates whose files carry no useful tags, which
  is common enough to matter: without it those items reach the operator with
  nothing to search on but a filename.

  Release naming has no standard, so nothing here is trusted — the output is
  a *hint* used to build a provider query and to prefill the inbox item, and
  everything it produces is reviewed before it becomes a record. It's tuned
  against a real 295-release downloads folder, and the shapes it handles are
  the ones that actually occur there:

      Cory Doctorow - The Bezzle [m4b]
      Dan Brown ~ [Robert Langdon 06] - The Secret of Secrets (M4b)
      Olan Thorensen - A Fearful Symmetry Destiny's Crucible, Book 8
      Discworld 30 The Wee Free Men (Read by Steven Briggs - Clear sound)
      Sunrise on the Reaping [B0D6PCZ98M]
      01 Angels and Demons.m4b

  When it can't tell an author from a title it says so (`author: nil`) rather
  than guessing, because a wrong author is worse than a missing one: it sends
  the provider search off in the wrong direction entirely.
  """

  alias Ambry.Inbox.ReleaseName

  defstruct [
    :title,
    :author,
    :narrator,
    :series,
    :series_number,
    :asin,
    :part_number,
    :parts_total
  ]

  # Quality/format noise that shows up in brackets and parens.
  #
  # `disc` and the bare small number are a pair: `noise?/1` splits a bracket
  # on whitespace and requires *every* word to be noise, so "[Disc 1]" needs
  # both halves listed. The bare number also finishes the job `cd\d*` only
  # half did — it matched "CD1" but never "CD 1".
  @noise ~r/^(m4b|mp3|m4a|flac|ogg|opus|aax|aaxc|unabridged|abridged|audiobook|
              retail|complete|chapterized|chaptered|dramatized|dramatised|graphicaudio|
              \d{4}|\d+\s*k(bps)?|\d+kb|v\d+|cd\d*|discs?\d*|web|h?\d{2,3}\.\d+|
              \d{1,3}|\d+(\.\d+)?\s*(mb|gb)|\d{1,2}[.:]\d{2}[.:]\d{2})$/xi

  @asin ~r/\b(B0[A-Z0-9]{8})\b/

  @doc """
  Parses a release name into whatever it can identify.
  """
  def parse(name) when is_binary(name) do
    base = name |> Path.basename() |> strip_extension()

    {narrator, base} = extract_narrator(base)
    asin = extract_asin(base)
    {part, base} = extract_part(base)
    {series_hint, base} = extract_bracketed_series(base)
    base = strip_bracketed(base)

    {author, title} = base |> collapse_spaces() |> split_author_title()
    {series, series_number} = series_hint || series_from_title(title)

    %ReleaseName{
      title: title |> strip_trailing_series() |> presence(),
      author: presence(author),
      narrator: narrator,
      series: presence(series),
      series_number: series_number,
      asin: asin,
      part_number: part && elem(part, 0),
      parts_total: part && elem(part, 1)
    }
  end

  @doc """
  Strips release junk from a title that arrived by some other road — embedded
  tags, mostly.

  Tag titles carry the same noise folder names do ("Children of Time
  (Unabridged)", "Project Hail Mary [m4b]"), but unlike a zero-result search a
  noisy one *succeeds*, with sub-par results — so the plainer-title retry that
  rescues failed searches never fires. Parentheticals carrying real title
  material ("(A Court of Thorns and Roses #2)") are kept, by the same noise
  test the parser applies.

  Returns nil when nothing but noise remains, so callers fall back exactly as
  they would for a missing tag.
  """
  def strip_noise(title) when is_binary(title) do
    title
    |> remove_noise_brackets()
    |> remove_noise_parens()
    |> remove_noise_subtitle()
    |> remove_series_tail()
    |> remove_part_phrase()
    |> remove_sequence_numbers()
    |> collapse_spaces()
    |> presence()
  end

  def strip_noise(_other), do: nil

  # "Part N of M" and its spellings — a release's place in a part set
  # (GraphicAudio's shape), stated in the file name or a tag title's tail.
  # Sanity-gated: the numbers must read as a position in a set, or "2 of
  # Swords" and "1 of 1000" become parts. The bare trailing form gets the
  # tighter cap — it has no "part" keyword vouching for it.
  @part_explicit ~r/\b(?:part|pt\.?)\s*(\d{1,3})\s*(?:of|\/)\s*(\d{1,3})\b/i
  @part_paren ~r/\((\d{1,3})\s+of\s+(\d{1,3})\)/
  @part_trailing ~r/\b(\d{1,3})\s+of\s+(\d{1,3})\s*$/

  defp extract_part(base) do
    extract_part_with(base, @part_explicit, 50) ||
      extract_part_with(base, @part_paren, 50) ||
      extract_part_with(base, @part_trailing, 20) ||
      {nil, base}
  end

  defp extract_part_with(base, regex, max_total) do
    with [match, number, total] <- Regex.run(regex, base),
         {number, total} = {String.to_integer(number), String.to_integer(total)},
         true <- number >= 1 and number <= total and total <= max_total do
      {{number, total}, String.replace(base, match, " ")}
    else
      _no_part -> nil
    end
  end

  # Tag titles carry the same phrase ("…A Court of Thorns and Roses 1 of 2"),
  # and like the other noise it poisons the provider query while still
  # returning *something*, so the zero-result retry never rescues it.
  defp remove_part_phrase(title) do
    case extract_part(title) do
      {nil, _base} -> title
      {_part, cleaned} -> cleaned
    end
  end

  # Deliberately strict. "Disc 02" and "3 of 5" are parts; "Gwendy's Button
  # Box 2" and "01 - The Restaurant at the End of the Universe" are their own
  # books, and a looser pattern (anything ending in a number) would swallow
  # them into one item.
  @part_folder ~r/^(disc|cd|part|vol|volume)\s*\.?\s*\d+$|^\d+\s*of\s*\d+$|\((disc|cd|part)\s*\d+\)$/i

  @doc """
  Whether a folder name states nothing but a position in a set.

  Discovery reads it to decide that a folder of such subfolders is one
  release rather than several, and an item named after one reads it to say
  which release it belongs to — "1 of 5" alone names nothing.
  """
  def part_folder?(name) when is_binary(name),
    do: name |> String.trim() |> then(&Regex.match?(@part_folder, &1))

  def part_folder?(_other), do: false

  @doc """
  The part-set position a name states, as `{number, total}`, or nil.

  For provider record titles — Audible lists GraphicAudio parts as
  "The Way of Kings (1 of 3)" — where the caller wants the fact without the
  rest of the parse.
  """
  def part_of(name) when is_binary(name) do
    case extract_part(name) do
      {nil, _base} -> nil
      {part, _base} -> part
    end
  end

  def part_of(_other), do: nil

  # Album tags carry shelf ordering the way folder names do: the operator's
  # Mr. Mercedes is tagged "01 Mr. Mercedes" and Limitless "Limitless 01",
  # and both sent the provider search into junk ("01 Mistrunner" led at
  # 0.569, the right book absent). A leading track number mirrors the
  # parser's rule; a trailing one only goes when zero-padded — "Limitless
  # 01" is ordering, "Judicator Jane 4" and "Fahrenheit 451" are titles.
  defp remove_sequence_numbers(title) do
    title
    |> String.replace(~r/^\d{1,3}[-.\s]+(?=\D)/, "")
    |> String.replace(~r/[-.\s]+0\d\s*$/, "")
  end

  # "Jurassic Park: A Novel" — a marketing subtitle that carries no
  # information and sends provider search sideways: with it, neither
  # provider returned the actual book (The Lost World and Jurassic Park III
  # led instead), and because they returned *something*, the zero-result
  # plainer-title retry never fired. Only these known pure-noise phrases go;
  # a real subtitle disambiguates and stays.
  @noise_subtitle ~r/\s*[:—-]\s+an?\s+(novel|memoir|thriller|mystery|novella)\s*$/i

  defp remove_noise_subtitle(title), do: Regex.replace(@noise_subtitle, title, "")

  # "Kill Joy - A Good Girl's Guide to Murder Series, Book 0" — the series
  # statement a tag title carries in its tail. Real information, which is why
  # only the *query* loses it: the series parser reads its own fields off the
  # unstripped title, and the verbatim tag stays on offer as a chip. As a
  # title search it is poison — the catalogue title is "Kill Joy", and the
  # whole string returns nothing from any provider.
  #
  # A separator has to introduce it, and the run before "Series" may not
  # cross another one, so a book actually called "The Series" keeps its name.
  @series_tail ~r/\s*[-–—:,]\s*[^-–—:]*\bseries,?\s+book\s+[\d.]+\s*$/i

  # The same tail without the word, which only a comma is trusted to
  # introduce: "Wayfarers, Book 4" is a statement about a series, while
  # "Book 4" attached by a dash could be the title.
  @book_tail ~r/,\s*book\s+[\d.]+\s*$/i

  defp remove_series_tail(title) do
    title
    |> then(&Regex.replace(@series_tail, &1, ""))
    |> then(&Regex.replace(@book_tail, &1, ""))
  end

  @doc """
  The best search string for a provider: title and author when both are
  known, title alone otherwise.
  """
  def query(%ReleaseName{title: nil}), do: nil
  def query(%ReleaseName{title: title, author: nil}), do: title
  def query(%ReleaseName{title: title, author: author}), do: "#{title} #{author}"

  @audio_extensions ~w(.mp3 .m4b .m4a .mp4 .flac .ogg .opus .wav)

  defp strip_extension(name) do
    extension = name |> Path.extname() |> String.downcase()

    if extension in @audio_extensions, do: Path.rootname(name), else: name
  end

  # "(Read by Steven Briggs - Clear sound)" — a narrator credit hiding in the
  # folder name, worth keeping and definitely worth removing before the rest
  # of the parse sees that dash.
  defp extract_narrator(base) do
    case Regex.run(~r/\((?:read|narrated)\s+by\s+([^)\-]+)[^)]*\)/i, base) do
      [match, narrator] ->
        {narrator |> String.trim() |> presence(), String.replace(base, match, "")}

      nil ->
        {nil, base}
    end
  end

  defp extract_asin(base) do
    case Regex.run(@asin, base) do
      [_match, asin] -> asin
      nil -> nil
    end
  end

  # "[Robert Langdon 06]" — a series and its number, stated outright.
  defp extract_bracketed_series(base) do
    case Regex.run(~r/\[([^\]]*?[a-z][^\]]*?)\s*#?\s*(\d+(?:\.\d+)?)\]/i, base) do
      [match, series, number] ->
        if Regex.match?(@asin, match) or noise?(series) do
          {nil, base}
        else
          {{String.trim(series), to_decimal(number)}, String.replace(base, match, "")}
        end

      nil ->
        {nil, base}
    end
  end

  defp strip_bracketed(base) do
    base
    |> String.replace(~r/\[[^\]]*\]|\{[^}]*\}/, " ")
    |> remove_noise_parens()
  end

  # A release name's brackets are junk wholesale (`strip_bracketed/1`); a tag
  # title's are junk only when they say so — "[Unabridged]", "[m4b]".
  defp remove_noise_brackets(base) do
    Regex.replace(~r/\[([^\]]*)\]|\{([^}]*)\}/, base, fn match, bracket, brace ->
      if noise?(bracket <> brace), do: " ", else: match
    end)
  end

  # Parens carry both noise ("(Unabridged)", "(M4b)") and real title material
  # ("(A Court of Thorns and Roses #2)"), so only the noise goes.
  defp remove_noise_parens(base) do
    Regex.replace(~r/\(([^)]*)\)/, base, fn match, inner ->
      if noise?(inner), do: " ", else: match
    end)
  end

  defp noise?(text) do
    trimmed = String.trim(text)

    cond do
      trimmed == "" -> true
      Regex.match?(@noise, trimmed) -> true
      true -> trimmed |> String.split(~r/[\s,]+/, trim: true) |> all_noise?()
    end
  end

  defp all_noise?([]), do: true
  defp all_noise?(parts), do: Enum.all?(parts, &Regex.match?(@noise, &1))

  # "Author - Title" and "Author ~ Title" are the common shapes. A leading
  # track number ("01 Angels and Demons") is an ordering artifact, not an
  # author.
  defp split_author_title(base) do
    base =
      base
      |> then(&Regex.replace(~r/^\d{1,3}[-.\s]+(?=\D)/, &1, ""))
      |> drop_trailing_noise_segments()

    case Regex.run(~r/^(.+?)\s+by\s+([A-Z][^,]*(?:,\s*.+)?)$/, base) do
      [_match, title, author] -> {String.trim(author), String.trim(title)}
      nil -> split_on_dash(base)
    end
  end

  defp split_on_dash(base) do
    base = String.replace(base, ~r/^\s*[-~–—]\s+/, "")

    case String.split(base, ~r/\s+[-~–—]\s+/, parts: 2) do
      [author, title] -> maybe_author(author, title)
      [only] -> {nil, String.trim(only)}
    end
  end

  # "The Calculating Stars - 2018 - 125 kbps": everything after the title is
  # release bookkeeping, and it would otherwise ride along into the query.
  defp drop_trailing_noise_segments(base) do
    base
    |> String.split(~r/\s+[-~–—]\s+/)
    |> Enum.reverse()
    |> Enum.drop_while(&noise?/1)
    |> Enum.reverse()
    |> Enum.join(" - ")
    |> then(&if(&1 == "", do: base, else: &1))
  end

  # A "Series 03" prefix before the dash is a series, not a person, and a
  # very long left side is a title that happened to contain a dash.
  defp maybe_author(left, right) do
    left = String.trim(left)
    right = right |> String.replace(~r/^\s*[-~–—]\s*/, "") |> String.trim()

    cond do
      left == "" -> {nil, right}
      Regex.match?(~r/\d/, left) -> {nil, right}
      String.length(left) > 40 -> {nil, "#{left} - #{right}"}
      true -> {left, right}
    end
  end

  # "A Fearful Symmetry Destiny's Crucible, Book 8" — the series trails the
  # title with an explicit book number.
  defp series_from_title(title) do
    case Regex.run(
           ~r/[:;,]\s*([^:;,]+?),?\s+(?:book|bk\.?|vol\.?|volume)\s+(\d+(?:\.\d+)?)\s*$/i,
           title
         ) do
      [_match, series, number] ->
        {String.trim(series), to_decimal(number)}

      nil ->
        # "A Fearful Symmetry Destiny's Crucible, Book 8" — nothing marks
        # where the title stops and the series starts, and guessing costs the
        # title. Keep the number, leave the series for the operator.
        case Regex.run(~r/,?\s+(?:book|bk\.?|vol\.?|volume)\s+(\d+(?:\.\d+)?)\s*$/i, title) do
          [_match, number] -> {nil, to_decimal(number)}
          nil -> series_from_hash(title)
        end
    end
  end

  # "(A Court of Thorns and Roses #2)"
  defp series_from_hash(title) do
    case Regex.run(~r/\(([^)#]+)#\s*(\d+(?:\.\d+)?)\)/, title) do
      [_match, series, number] -> {String.trim(series), to_decimal(number)}
      nil -> {nil, nil}
    end
  end

  defp strip_trailing_series(title) do
    title
    |> String.replace(
      ~r/[:;,]\s*[^:;,]+,?\s+(?:book|bk\.?|vol\.?|volume)\s+\d+(?:\.\d+)?\s*$/i,
      ""
    )
    |> String.replace(~r/,?\s+(?:book|bk\.?|vol\.?|volume)\s+\d+(?:\.\d+)?\s*$/i, "")
    |> String.replace(~r/\([^)#]+#\s*\d+(?:\.\d+)?\)/, "")
    |> String.trim()
    |> String.trim_trailing(",")
    |> String.trim()
  end

  defp collapse_spaces(text) do
    text
    |> String.replace(~r/[_\s]+/, " ")
    |> String.replace(~r/\s+([-~–—])\s+\1\s+/, " \\1 ")
    |> String.trim()
    |> String.trim_leading("-")
    |> String.trim_leading("~")
    # a separator left dangling by a removed phrase (" - Part 1 of 2" at the
    # end of a name) is junk the same way a leading one is
    |> String.trim_trailing("-")
    |> String.trim_trailing("~")
    |> String.trim()
  end

  defp to_decimal(string) do
    case Decimal.parse(string) do
      {decimal, ""} -> decimal
      _unparseable -> nil
    end
  end

  defp presence(nil), do: nil
  defp presence(string), do: with("" <- String.trim(string), do: nil)
end
