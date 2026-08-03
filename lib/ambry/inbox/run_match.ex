defmodule Ambry.Inbox.RunMatch do
  @moduledoc """
  Proposes what one inbox item is.

  Kept to one at a time on purpose. A first scan of a real library means
  hundreds of lookups, and the public metadata instances are shared services
  that rate-limit — so this trades wall-clock for being a well-behaved
  client, and the queue drains in the background either way.
  """

  use Oban.Worker,
    queue: :metadata,
    max_attempts: 1,
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
end
