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
  def perform(%Oban.Job{args: %{"inbox_item_id" => id} = args}) do
    case Inbox.fetch_item(id) do
      # An operator-initiated rescan re-walks the folder first and re-asks the
      # providers with the cache bypassed; the automatic one probes the files
      # discovery already found.
      {:ok, item} -> if args["refresh"], do: Inbox.rescan_item(item), else: Inbox.probe_item(item)
      # the operator deleted it while the job was queued
      {:error, :not_found} -> :ok
    end
  end
end
