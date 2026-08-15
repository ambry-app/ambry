defmodule Ambry.Inbox.Claims do
  @moduledoc """
  What the file says about itself, read through the operator.

  Matching used to read `item.tags` and `item.path` directly. That made the
  files the one source of truth in the import form nobody could argue with:
  every provider record can be un-ticked, every field reverted, every credit
  renamed, but a release whose author tag holds its *narrator* had no control
  that said so. Re-searching by hand didn't fix it either, because a typed
  query changes the question while the answer is still graded against the
  tags. Measured across the operator's queue: twelve items whose title
  matched a catalogue record exactly and whose only defect was the author
  tag, in four unrelated shapes (a series name, a narrator, a studio, and one
  where the tag was right and the catalogue was wrong).

  So a tag is a **claim**, and a claim can be rejected. Everything that
  searches, scores or verifies reads through here.

  ## One box per source, not one per field

  Rejecting a tag cannot mean "the field is unstated", because `hints/1` is
  tags first and the release name second: blanking the author tag on
  `Bafflegab Productions - The Hellbound Heart` makes the parser lift the
  same junk straight back out of the folder name. A checkbox that silently
  swaps one bad source for another is worse than no checkbox.

  So the release name and the file names are claims too, with their own
  boxes. Two independent rejections, no third state, and nothing to fall
  through to once both are off.

  ## Rejecting reaches the back-match as well

  `AutoMatch.apply_narrator_evidence/2` searches the file's raw text for a
  candidate's readers, and that text is built from these same sources. A
  rejection that governed searching but not verifying would be a half
  answer to "this isn't right".

  It is safe in the direction that matters: the back-match only penalises a
  candidate when a *rival's* reader is named, so removing text makes it
  no-op more often. Rejecting a source can cost a corroboration bonus or a
  contradiction penalty; it cannot invent an answer.

  ## What is not here

  Editing a value. The form already has a search box the operator can write
  a better question into, and an edit control would raise the question of
  whether it writes back to the files, which is a different feature with a
  different blast radius.
  """

  alias Ambry.Inbox.InboxItem
  alias Ambry.Inbox.ReleaseName

  # The release name and the file names, keyed apart from the tags so a tag
  # named `files` could never collide with them.
  @release_name "name"
  @file_names "files"

  # The tag fields something actually consumes, in the order the panel shows
  # them. Anything not listed is not rejectable because nothing reads it.
  @tag_keys ~w(book_title authors narrators series series_number asin published publisher description has_cover_art)

  @doc "The claim keys, in display order."
  def keys, do: [@release_name, @file_names] ++ Enum.map(@tag_keys, &"tag:#{&1}")

  @doc "Whether the operator has rejected this claim."
  def rejected?(%InboxItem{rejected_claims: rejected}, key) when is_list(rejected),
    do: key in rejected

  def rejected?(_item, _key), do: false

  @doc """
  The item's tags, minus the rejected ones.

  Returned in the same shape `item.tags` has, because every reader of it
  wants that shape and the point is to be a drop-in.
  """
  def tags(%InboxItem{tags: tags} = item) when is_map(tags) do
    Enum.reduce(@tag_keys, tags, fn key, acc ->
      if rejected?(item, "tag:#{key}"), do: Map.delete(acc, key), else: acc
    end)
  end

  def tags(_item), do: %{}

  @doc """
  The release name parsed, or nothing if the operator rejected it.

  Nothing is an empty `ReleaseName` rather than nil so callers keep reading
  fields off it — a rejected name states nothing, which is exactly what an
  empty struct says.
  """
  def parsed_name(%InboxItem{path: path} = item) when is_binary(path) do
    if rejected?(item, @release_name), do: %ReleaseName{}, else: ReleaseName.parse(path)
  end

  def parsed_name(_item), do: %ReleaseName{}

  @doc """
  Everything the item says about itself, unparsed, for the back-match.

  Basenames only: the parent directories are the source root, which is the
  operator's filesystem layout and says nothing about this release.
  """
  def raw_text(%InboxItem{} = item) do
    []
    |> Enum.concat(
      if rejected?(item, @release_name), do: [], else: [Path.basename(item.path || "")]
    )
    |> Enum.concat(
      if rejected?(item, @file_names),
        do: [],
        else: Enum.map(item.files || [], &Path.basename/1)
    )
    |> Enum.concat(item |> tags() |> tag_text())
    |> Enum.join(" ")
  end

  defp tag_text(tags) when is_map(tags),
    do: tags |> Map.values() |> List.flatten() |> Enum.filter(&is_binary/1)

  @doc """
  Turns a claim on or off.

  Returns the new rejection list; storing it is `Ambry.Inbox`'s job, because
  a claim changing is what makes the stored scores stale.
  """
  def toggle(%InboxItem{rejected_claims: rejected}, key) do
    rejected = rejected || []

    if key in rejected, do: rejected -- [key], else: Enum.uniq(rejected ++ [key])
  end

  @doc """
  What the panel renders: one row per claim the item actually makes.

  A claim the file doesn't make gets no row — an empty tag is nothing to
  agree or disagree with, and a checkbox beside it would be a control that
  changes nothing.
  """
  def rows(%InboxItem{} = item) do
    tags = item.tags || %{}

    name_rows =
      [
        {@release_name, "release name", presence(item.path && Path.basename(item.path))},
        {@file_names, "file names", file_summary(item.files)}
      ]

    tag_rows =
      for key <- @tag_keys, value = format(tags[key]), value != nil do
        {"tag:#{key}", label(key), value}
      end

    for {key, label, value} <- name_rows ++ tag_rows, value != nil do
      %{key: key, label: label, value: value, accepted: not rejected?(item, key)}
    end
  end

  defp file_summary([]), do: nil
  defp file_summary(nil), do: nil
  defp file_summary([one]), do: Path.basename(one)
  defp file_summary(files), do: "#{length(files)} files"

  defp label("book_title"), do: "title"
  defp label("series_number"), do: "series no."
  defp label("has_cover_art"), do: "embedded cover"
  defp label(key), do: String.replace(key, "_", " ")

  # `has_cover_art` is a boolean whose false is a non-claim: the file saying
  # it has no art is not something to reject.
  defp format(true), do: "yes"
  defp format(false), do: nil
  defp format(value) when is_list(value), do: value |> Enum.join(", ") |> presence() |> clip()
  defp format(nil), do: nil
  defp format(value), do: value |> to_string() |> presence() |> clip()

  # A row is a checkbox with enough beside it to recognise what is being
  # rejected. Descriptions run to whole paragraphs of publisher HTML, and a
  # panel that renders one in full buries the nine rows under it.
  @clip 70

  defp clip(nil), do: nil

  defp clip(string) do
    string = strip_markup(string)

    if String.length(string) > @clip,
      do: String.slice(string, 0, @clip) <> "…",
      else: string
  end

  # Publisher descriptions arrive as HTML, and seventy characters of
  # `<p><b>At last, the story that` identifies nothing. The value is being
  # shown so the operator can recognise which claim the box belongs to, not
  # read it.
  defp strip_markup(string) do
    string
    |> String.replace(~r/<[^>]*>/, " ")
    |> String.replace(~r/&[a-z]+;|&#\d+;/i, " ")
    |> String.replace(~r/\s+/, " ")
    # A tag closing mid-sentence leaves its space in front of the punctuation
    # that followed it: "<b>At last</b>, the story" reads "At last , the".
    |> String.replace(~r/\s+([,.;:!?])/, "\\1")
    |> String.trim()
  end

  defp presence(nil), do: nil
  defp presence(string), do: with("" <- String.trim(string), do: nil)
end
