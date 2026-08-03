defmodule Ambry.Media.RunPublishPending do
  @moduledoc """
  Releases the direct-play recordings the publishing switch was holding back.

  Runs when the operator turns the switch on. A large library shouldn't make
  that click take a minute, and nothing about it needs to be synchronous.
  """

  use Oban.Worker,
    queue: :media,
    max_attempts: 3

  alias Ambry.Media

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    {:ok, counts} = Media.publish_pending_direct_play()
    Logger.info(fn -> "Published pending direct-play recordings: #{inspect(counts)}" end)
    :ok
  end
end
