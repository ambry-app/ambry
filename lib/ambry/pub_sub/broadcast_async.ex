defmodule Ambry.PubSub.BroadcastAsync do
  @moduledoc false
  use Oban.Worker,
    queue: :pub_sub,
    max_attempts: 1

  alias Ambry.PubSub
  alias Ambry.PubSub.Message

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    args
    |> Message.cast()
    |> PubSub.broadcast()
  end
end
