defmodule Ambry.PubSub.AsyncBroadcast do
  @moduledoc false
  use Oban.Worker,
    queue: :pub_sub,
    max_attempts: 1

  alias Ambry.PubSub
  alias Ambry.PubSub.MessageNew

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    args
    |> MessageNew.cast()
    |> PubSub.broadcast()
  end
end
