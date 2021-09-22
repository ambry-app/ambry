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

  # convenience functions

  def pub(:playback_started, user_id, client_id, media_id) do
    broadcast(
      "users:#{user_id}-#{client_id}:playback-started:#{media_id}",
      {:playback_started, media_id}
    )

    broadcast(
      "users:*:playback-started:*",
      {:playback_started, user_id, client_id, media_id}
    )
  end

  def pub(:playback_paused, user_id, client_id, media_id) do
    broadcast(
      "users:#{user_id}-#{client_id}:playback-paused:#{media_id}",
      {:playback_paused, media_id}
    )

    broadcast(
      "users:*:playback-paused:*",
      {:playback_paused, user_id, client_id, media_id}
    )
  end

  def pub(:load_and_play_media, user_id, client_id, media_id) do
    broadcast(
      "users:#{user_id}-#{client_id}:load-and-play-media",
      {:load_and_play_media, media_id}
    )
  end

  def pub(:pause, user_id, client_id) do
    broadcast(
      "users:#{user_id}-#{client_id}:pause",
      :pause
    )
  end

  def sub(:playback_started) do
    subscribe("users:*:playback-started:*")
  end

  def sub(:playback_paused) do
    subscribe("users:*:playback-paused:*")
  end

  def sub(:playback_started, user_id, client_id, media_id) do
    subscribe("users:#{user_id}-#{client_id}:playback-started:#{media_id}")
  end

  def sub(:playback_paused, user_id, client_id, media_id) do
    subscribe("users:#{user_id}-#{client_id}:playback-paused:#{media_id}")
  end

  def sub(:load_and_play_media, user_id, client_id) do
    subscribe("users:#{user_id}-#{client_id}:load-and-play-media")
  end

  def sub(:pause, user_id, client_id) do
    subscribe("users:#{user_id}-#{client_id}:pause")
  end
end
