defmodule Ambry.Inbox.RunMatch do
  @moduledoc """
  Proposes what one inbox item is.

  Kept to one at a time on purpose. Cold-starting a server from an existing
  collection means hundreds of lookups against shared metadata instances that
  rate-limit — so this trades wall-clock for being a well-behaved client, and
  the queue drains in the background either way. Day to day it's a handful of
  books, where the serialisation costs nothing.

  Because nothing waits on it, matching is allowed to be **thorough**: search
  every enabled provider, fetch full details for the records about the top
  work, and ask every editions-capable database what recordings that work has.

  ## Retries

  A rate-limited provider used to cost an item its records permanently — one
  attempt, and the failure survived only as a discarded job that the Oban
  pruner deletes within a day. Now it backs off and tries again, and the
  operator can retry a single provider from the form besides.
  """

  use Oban.Worker,
    queue: :metadata,
    max_attempts: 5,
    unique: [period: 60, fields: [:worker, :args]]

  alias Ambry.Inbox

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"inbox_item_id" => id}}) do
    case Inbox.fetch_item(id) do
      {:ok, item} -> Inbox.match_item(item)
      # the operator deleted it while the job was queued
      {:error, :not_found} -> :ok
    end
  end

  # Shared instances rate-limit with a ~30s Retry-After, so the first retry
  # waits past that rather than immediately spending another request on being
  # told no.
  @impl Oban.Worker
  def backoff(%Oban.Job{attempt: attempt}), do: trunc(:math.pow(2, attempt) * 30)
end
