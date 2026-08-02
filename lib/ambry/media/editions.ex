defmodule Ambry.Media.Editions do
  @moduledoc """
  Editions — the first-class "Audiobook or Group" union (tile system v2).

  An edition is one recorded edition of a book: either a single audiobook
  or a recording group (a multi-part set). This module is the one
  implementation of grouping, representative choice, and ordering for
  every tile surface; the library listing and the admin flat views carry
  an SQL twin of the representative rule for pagination, held in lockstep
  by tests.

  The rules (ROADMAP "Tile system v2", operator-authored):

    * parts order within a group: part number (nulls last), then id
    * a group with only one visible part presents as a single edition —
      a one-part "set" is noise, not a stack
    * representative: the first part / the audiobook itself
    * editions order: representative publish date, newest first (a
      group's date IS its first part's date), nulls last, id tiebreak
  """

  alias Ambry.Media.Media
  alias Ambry.Media.RecordingGroup

  defmodule Edition do
    @moduledoc "One recorded edition of a book: a single audiobook or a part set."

    defstruct [:kind, :media, :representative, :group]

    @type t :: %__MODULE__{
            kind: :single | :group,
            media: [struct()],
            representative: struct(),
            group: struct() | nil
          }
  end

  @doc """
  Partitions a book's media list into editions, newest first.

  Only ready media are considered unless `all_statuses: true` (admin
  surfaces — operators always see non-ready). A book whose media are all
  filtered out yields `[]` — user-facing surfaces hide such books
  entirely.
  """
  def from_media(media_list, opts \\ []) do
    media_list =
      if opts[:all_statuses],
        do: media_list,
        else: Enum.filter(media_list, &(&1.status == :ready))

    {grouped, singles} = Enum.split_with(media_list, & &1.recording_group_id)

    group_editions =
      grouped
      |> Enum.group_by(& &1.recording_group_id)
      |> Enum.map(fn {_group_id, parts} ->
        parts
        |> Enum.sort_by(&{&1.part_number || :infinity, &1.id})
        |> group_edition()
      end)

    single_editions = Enum.map(singles, &single_edition/1)

    sort_newest_first(group_editions ++ single_editions)
  end

  @doc """
  Wraps one listing row into its edition, for surfaces that select
  representatives SQL-side (the library): a grouped row must arrive with
  its recording group's visible media preloaded in part order. The row
  itself stays the representative — the SQL already chose the first ready
  part, and the row carries the preloads (book, narrators) the tile needs.
  """
  def from_representative(%Media{} = media) do
    case media do
      %{recording_group: %RecordingGroup{media: [_, _ | _] = parts} = group} ->
        %Edition{kind: :group, media: parts, representative: media, group: group}

      _single_or_lone_part ->
        single_edition(media)
    end
  end

  defp group_edition([only_part]), do: single_edition(only_part)

  defp group_edition([representative | _rest] = parts) do
    %Edition{
      kind: :group,
      media: parts,
      representative: representative,
      group: loaded_group(representative)
    }
  end

  defp single_edition(media) do
    %Edition{kind: :single, media: [media], representative: media, group: nil}
  end

  defp loaded_group(%Media{recording_group: %RecordingGroup{} = group}), do: group
  defp loaded_group(_media), do: nil

  @epoch {0, 1, 1}

  defp sort_newest_first(editions) do
    Enum.sort_by(
      editions,
      fn %Edition{representative: rep} ->
        {(rep.published && Date.to_erl(rep.published)) || @epoch, rep.id}
      end,
      :desc
    )
  end
end
