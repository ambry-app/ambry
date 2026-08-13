defmodule Ambry.Inbox.RunImport do
  @moduledoc """
  Adds one settled inbox item to the library.

  ## Why this is a job and not a click

  Importing is the longest thing the inbox does: every file is re-probed and
  then every byte is placed. Measured on a 28-file release, that is seven
  seconds of ffprobe plus a 131MB copy, and a copy off a NAS is slower still.

  Run from the form it was held in an async task owned by the LiveView, which
  meant the operator had to sit on the page and watch it — and worse, the task
  **died with the LiveView**. Navigating away or closing the tab killed an
  import mid-copy. The transaction protected the records, but nothing about
  the arrangement was honest: a long, resumable-by-nobody operation hanging
  off a browser tab.

  As a job it belongs to the server. The operator presses the button and goes
  back to the queue, where the row wears the same busy overlay every other
  background job gives it — because `Ambry.Inbox.Progress` derives that
  overlay from the job table, and this worker is simply one more entry there.

  ## Failure is reported on the item, not by the job

  `Inbox.import_item/1` already writes what went wrong onto the item's
  `issue`, in the same sentence the form used to flash. So a refused import
  returns `:ok` here rather than failing the job: a discarded job is deleted
  by the pruner within a day, while the issue is still on the row tomorrow,
  which is when somebody actually reads it. Only an unexpected crash is
  allowed to discard, because that is the one case with nothing recorded
  anywhere else.

  `max_attempts: 1` for the same reason it is 1 on probe and discovery — the
  refusals are decisions (a destination already occupied, a missing
  publication date), and none of them fixes itself by being tried again.
  """

  use Oban.Worker,
    queue: :media,
    max_attempts: 1,
    # The button is behind a busy overlay the moment the first job is
    # enqueued, but a stale tab can still send the event twice. The row lock
    # in `Importer` is what makes a double import safe; this is what stops it
    # being attempted.
    unique: [period: :infinity, states: Oban.Job.states() -- [:completed, :discarded, :cancelled]]

  alias Ambry.Inbox

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"inbox_item_id" => id}}) do
    case Inbox.fetch_item(id) do
      {:ok, item} -> import_item(item)
      # the operator deleted it while the job was queued
      {:error, :not_found} -> :ok
    end
  end

  defp import_item(item) do
    case Inbox.import_item(item) do
      {:ok, _media} ->
        :ok

      {:error, reason} ->
        Logger.warning(fn -> "Inbox import: item #{item.id} refused: #{inspect(reason)}" end)
        :ok
    end
  end
end
