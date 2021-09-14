defmodule Ambry.PubSub do
  @moduledoc """
  Helper functions for publishing and subscribing to Ambry events.
  """

  alias Phoenix.PubSub

  @doc """
  Subscribe to a topic.
  """
  def subscribe(topic), do: PubSub.subscribe(__MODULE__, topic)

  @doc """
  Broadcast a message to a topic.
  """
  def broadcast(topic, message), do: PubSub.broadcast(__MODULE__, topic, message)
end
