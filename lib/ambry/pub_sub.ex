defmodule Ambry.PubSub do
  @moduledoc """
  Helper functions for publishing and subscribing to Ambry events.
  """

  alias Ambry.Media.Media
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
  def broadcast_create(value), do: broadcast(value, :created)

  @doc """
  Broadcasts an "updated" event for a struct.
  """
  def broadcast_update(value), do: broadcast(value, :updated)

  @doc """
  Broadcasts a "deleted" event for a struct.
  """
  def broadcast_delete(value), do: broadcast(value, :deleted)

  @doc """
  Broadcasts a "progress" event for a media.
  """
  def broadcast_progress(%Media{} = media, progress) do
    topic = "media-progress:#{media.id}"
    message = {:media, :progress, {media.id, progress}}

    broadcast_all([topic], message)
  end

  defp broadcast({:ok, value}, action), do: broadcast(value, action)

  defp broadcast(%mod{id: id}, action) do
    {topics, name} = topics_and_name(mod, id)

    broadcast_all(topics, {name, action, id})
  end

  defp broadcast(_else, _action), do: :noop

  defp broadcast_all([], _message), do: :ok

  defp broadcast_all([topic | rest], message) do
    case PubSub.broadcast(__MODULE__, topic, message) do
      :ok ->
        Logger.debug(fn -> "#{__MODULE__} Published to #{topic} - #{inspect(message)}" end)
        broadcast_all(rest, message)

      {:error, reason} ->
        Logger.warn(fn -> "#{__MODULE__} Failed publish to #{topic} - #{inspect(reason)}" end)
        {:error, reason}
    end
  end

  defp topics_and_name(module, id) do
    [last | _] = module |> Module.split() |> Enum.reverse()
    name = last |> Macro.underscore() |> String.to_atom()

    {["#{name}:#{id}", "#{name}:*"], name}
  end
end
