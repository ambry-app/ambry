defmodule Ambry.PubSub do
  @moduledoc """
  Helper functions for publishing and subscribing to Ambry events.
  """

  use Boundary, deps: [Ambry.Media], exports: [Message, Publishable]

  alias Ambry.Media.Media
  alias Ambry.PubSub.Message
  alias Ambry.PubSub.Publishable
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
  Broadcasts a "created" event for a struct.
  """
  def broadcast_create(value, meta \\ %{}), do: broadcast(value, :created, meta)

  @doc """
  Broadcasts an "updated" event for a struct.
  """
  def broadcast_update(value, meta \\ %{}), do: broadcast(value, :updated, meta)

  @doc """
  Broadcasts a "deleted" event for a struct.
  """
  def broadcast_delete(value, meta \\ %{}), do: broadcast(value, :deleted, meta)

  @doc """
  Broadcasts a "progress" event for a media.
  """
  def broadcast_progress(%Media{} = media, progress) do
    topic = "media-progress"
    message = %Message{type: :media, action: :progress, id: media.id, meta: %{progress: progress}}

    broadcast_all([topic], message)
  end

  defp broadcast(%mod{id: id} = data, action, meta) do
    message = %Message{type: type(mod), action: action, id: id, meta: meta}
    topics = Publishable.topics(data)

    broadcast_all(topics, message)
  end

  defp broadcast(not_a_struct, _action, _meta),
    do: raise("PubSub broadcast expected a struct, got #{inspect(not_a_struct)}")

  defp broadcast_all([], _message), do: :ok

  defp broadcast_all([topic | rest], message) do
    case PubSub.broadcast(__MODULE__, topic, message) do
      :ok ->
        Logger.debug(fn -> "#{__MODULE__} Published to #{topic} - #{inspect(message)}" end)
        broadcast_all(rest, message)

      {:error, reason} ->
        Logger.warning(fn -> "#{__MODULE__} Failed publish to #{topic} - #{inspect(reason)}" end)
        {:error, reason}
    end
  end

  def type(module) do
    [last | _] = module |> Module.split() |> Enum.reverse()
    last |> Macro.underscore() |> String.to_atom()
  end
end
