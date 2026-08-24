defmodule Ambry.SentryFilter do
  @moduledoc """
  Drops the reports Sentry can do nothing with, before they leave the node.

  Bandit raises `Bandit.TransportError` when a socket write fails and treats it
  as routine at its own boundary, deliberately skipping the `Logger.error`
  every other exception gets. But `Sentry.PlugCapture` is `use`d on the
  endpoint, which puts it *inside* that boundary, so it reports the exception
  as an unhandled crash before Bandit gets to shrug.

  For us that is the direct-play route: `send_file/5` does not return until
  every byte is on the wire, which for a player consuming a book at playback
  speed is the length of the listening session. A player that pauses, seeks or
  moves on hangs up mid-transfer, and nothing was owed to it.

  Sentry-side only. The exception still propagates and Bandit still handles it.

  """

  @doc """
  Sentry's `:before_send` callback. Returns `nil` to drop the event.
  """
  @spec before_send(Sentry.Event.t()) :: Sentry.Event.t() | nil
  def before_send(%Sentry.Event{original_exception: %Bandit.TransportError{}}), do: nil
  def before_send(%Sentry.Event{} = event), do: event
end
