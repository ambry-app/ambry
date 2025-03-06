defmodule Ambry.PubSub do
  @moduledoc """
  Helper functions for publishing and subscribing to Ambry events.
  """

  use Boundary,
    deps: [Ambry.Media, Ambry.People, Ambry.Books],
    exports: [
      Message
    ]

  alias Ambry.PubSub.AsyncBroadcast
  alias Phoenix.PubSub

  require Logger

  @doc """
  Subscribe to a topic.
  """
  def subscribe(topic) do
    Logger.debug(fn -> "#{__MODULE__} #{inspect(self())} subscribed to #{topic}" end)
    PubSub.subscribe(__MODULE__, topic)
  end

  @doc """
  Unsubscribe from a topic.
  """
  def unsubscribe(topic) do
    Logger.debug(fn -> "#{__MODULE__} #{inspect(self())} unsubscribed from #{topic}" end)
    PubSub.unsubscribe(__MODULE__, topic)
  end

  @doc """
  Broadcast messages to a list of topics
  """
  def broadcast_all([], _message), do: :ok

  def broadcast_all([topic | rest], message) do
    case PubSub.broadcast(__MODULE__, topic, message) do
      :ok ->
        Logger.debug(fn -> "#{__MODULE__} Published to #{topic} - #{inspect(message)}" end)
        broadcast_all(rest, message)

      {:error, reason} ->
        Logger.warning(fn -> "#{__MODULE__} Failed publish to #{topic} - #{inspect(reason)}" end)
        {:error, reason}
    end
  end

  @doc """
  Subscribe to messages from the listed modules.
  Each module must implement the Ambry.PubSub.Message behavior.
  """
  def subscribe_to_messages(messages) do
    messages
    |> Enum.map(& &1.subscribe_topic())
    |> Enum.uniq()
    |> Enum.map(&subscribe/1)
    |> Enum.uniq()
    |> case do
      [:ok] -> :ok
      _ -> :error
    end
  end

  @doc """
  Broadcast a message to all topics in its broadcast_topics field.
  """
  def broadcast(%_{broadcast_topics: topics} = message) do
    broadcast_all(topics, message)
  end

  @doc """
  Schedule a message to be broadcast asynchronously via Oban.
  """
  def broadcast_async(%module{} = message) do
    %{
      "module" => module,
      "message" => Map.from_struct(message)
    }
    |> AsyncBroadcast.new()
    |> Oban.insert()
  end
end
