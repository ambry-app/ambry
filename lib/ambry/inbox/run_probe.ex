defmodule Ambry.Inbox.RunProbe do
  @moduledoc """
  Records what one inbox item's files are, and what they claim about
  themselves.
  """

  use Oban.Worker,
    queue: :media,
    max_attempts: 1

  alias Ambry.Inbox

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"inbox_item_id" => id}}) do
    case Inbox.fetch_item(id) do
      {:ok, item} -> Inbox.probe_item(item)
      # the operator deleted it while the job was queued
      {:error, :not_found} -> :ok
    end
  end
end
