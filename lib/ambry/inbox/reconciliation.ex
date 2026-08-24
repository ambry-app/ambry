defmodule Ambry.Inbox.Reconciliation do
  @moduledoc """
  Noticing that an inbox item's files stopped being there.

  Discovery's walk only ever *claims* files, so an item whose files are all
  gone produces no claim: nothing refreshes it, and it sits in the queue with
  a stale file list looking perfectly importable until Add fails inside
  placement with `{:source_missing, path}`, after every decision has been
  made. This is the same job `Ambry.Media.Reconciliation` does for recordings,
  and the same answer: only ever *record* what was found. Nothing cascades and
  nothing is deleted.

  ## Why it asks the disk rather than the walk

  The walk knows which items it claimed files for, and "no claim" looks like
  a free answer. It isn't: ownership is a statement about which item a file
  belongs to, not about whether it exists, and reading one as the other ties
  this to a model that has nothing to do with it. Asking the filesystem
  directly is one `File.regular?` per file and answers the question that was
  actually asked.

  ## An unreachable source is not a missing item

  Nothing is checked unless the source's own directory is readable, which is
  the guard `Ambry.Inbox.scan/1` already applies before walking. A NAS that
  is unplugged this morning must not turn every item in the queue into an
  error, and one that comes back must not need a repair pass.

  ## Partly missing is missing

  An item is its files. A release that has lost one of forty cannot be
  imported as the recording the draft describes, and the count would be a
  fact nobody can act on differently — the fix is the same either way, and
  the import is blocked either way.

  ## Empty is not missing

  An item that lists no files has none that went away. "There was never any
  audio here" already has a better answer than this one — the importer
  refuses it as `:no_audio_files` — and reporting it as missing would trade a
  precise refusal for a vague one and send the operator looking for files
  that never existed.
  """

  import Ecto.Query

  alias Ambry.Inbox.InboxItem
  alias Ambry.Repo

  @doc """
  Checks every item of one source and records what it found.

  Returns `{:ok, %{checked: n, missing: n, healed: n}}`, or
  `{:error, :source_unreachable}` when the source's directory can't be read,
  in which case nothing is written.
  """
  def reconcile_source(source) do
    if File.dir?(source.path) do
      InboxItem
      |> where([i], i.source_id == ^source.id)
      |> Repo.all()
      |> Enum.map(&Repo.preload(&1, :source))
      |> Enum.reduce(%{checked: 0, missing: 0, healed: 0}, fn item, counts ->
        counts = Map.update!(counts, :checked, &(&1 + 1))

        case reconcile(item) do
          {:ok, :missing} -> Map.update!(counts, :missing, &(&1 + 1))
          {:ok, :healed} -> Map.update!(counts, :healed, &(&1 + 1))
          {:ok, :unchanged} -> counts
        end
      end)
      |> then(&{:ok, &1})
    else
      {:error, :source_unreachable}
    end
  end

  @doc """
  Checks one item and records the result.

  Returns `{:ok, :missing | :healed | :unchanged}`.
  """
  def reconcile(%InboxItem{} = item) do
    case {missing_files(item), item.missing_since} do
      {[], nil} -> {:ok, :unchanged}
      {[], _was_missing} -> put_missing_since(item, nil, :healed)
      {[_ | _], nil} -> put_missing_since(item, DateTime.utc_now(:second), :missing)
      {[_ | _], _already} -> {:ok, :unchanged}
    end
  end

  @doc """
  Whether this item's files are all still there.

  The question `reopen` and the import both ask, so there is one answer to
  it. Reads the stored flag rather than the disk: it is what the queue is
  rendering, and a control that disagreed with the badge beside it would be
  the worse of the two bugs.
  """
  def present?(%InboxItem{missing_since: nil}), do: true
  def present?(%InboxItem{}), do: false

  # An item that lists no files has none that are gone. "There was never any
  # audio here" is a different fact with a better answer already — the
  # importer refuses it as `:no_audio_files` — and calling it missing would
  # replace a precise refusal with a vague one and invite the operator to go
  # looking for files that never existed.
  defp missing_files(%InboxItem{files: []}), do: []

  defp missing_files(%InboxItem{} = item) do
    item
    |> InboxItem.owned_disk_files()
    |> Enum.reject(&File.regular?/1)
  end

  defp put_missing_since(item, missing_since, result) do
    item
    |> Ecto.Changeset.change(%{missing_since: missing_since})
    |> Repo.update()
    |> case do
      {:ok, _item} -> {:ok, result}
      {:error, _changeset} = error -> error
    end
  end
end
