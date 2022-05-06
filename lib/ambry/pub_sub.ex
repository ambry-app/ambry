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

  defp broadcast({:ok, value}, action), do: broadcast(value, action)

  defp broadcast(%mod{id: id}, action) do
    {topics, named_action} = topics_and_action(mod, id, action)

    broadcast_all(topics, {named_action, id})
  end

  defp broadcast(_else, _action), do: :noop

  defp broadcast_all([], _message), do: :ok

  defp broadcast_all([topic | rest], message) do
    case PubSub.broadcast(__MODULE__, topic, message) do
      :ok -> broadcast_all(rest, message)
      {:error, reason} -> {:error, reason}
    end
  end

  defp topics_and_action(module, id, action) do
    [last | _] = module |> Module.split() |> Enum.reverse()
    name = Macro.underscore(last)

    # This is safe because `action` is only one of three things and `name` is
    # generated from modules within this codebase. No user input.
    # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
    named_action = String.to_atom("#{name}_#{action}")

    {["#{name}:#{id}", "#{name}:*"], named_action}
  end
end
