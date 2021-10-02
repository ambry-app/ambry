defmodule Ambry.PlayerStateRegistry do
  @moduledoc """
  Keeps track of what users/browsers are playing which media.
  """

  use GenServer

  alias Ambry.PubSub

  ## Client API

  def start_link([]) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def is_playing?(user_id, browser_id, media_id) do
    key = key(user_id, browser_id, media_id)

    case :ets.lookup(__MODULE__, key) do
      [] -> false
      [{^key, value}] -> value
    end
  end

  ## Server callbacks

  @impl GenServer
  def init([]) do
    :ets.new(__MODULE__, [:named_table])

    PubSub.sub(:playback_started)
    PubSub.sub(:playback_paused)

    {:ok, []}
  end

  @impl GenServer
  def handle_info({:playback_started, user_id, browser_id, media_id}, []) do
    true = :ets.insert(__MODULE__, {key(user_id, browser_id, media_id), true})

    {:noreply, []}
  end

  def handle_info({:playback_paused, user_id, browser_id, media_id}, []) do
    true = :ets.insert(__MODULE__, {key(user_id, browser_id, media_id), false})

    {:noreply, []}
  end

  defp key(user_id, browser_id, media_id) do
    "#{user_id}-#{browser_id}-#{media_id}"
  end
end
