defmodule Ambry.SentryFilter do
  @moduledoc """
  Drops the reports Sentry can do nothing with, before they leave the node.

  Bandit raises `Bandit.TransportError` when a socket write fails, and treats
  it as routine at its own boundary: the clause of `Bandit.Pipeline.handle_error/7`
  that matches it deliberately skips the `Logger.error` every other exception
  gets, because a socket that went away is not a server fault. But
  `Sentry.PlugCapture` is `use`d on the endpoint, which puts it *inside* that
  boundary — it sees the exception on its way past and reports it as an
  unhandled crash before Bandit ever gets to shrug.

  For us that means the direct-play route. `AmbryWeb.FileResponse` answers a
  track request with `Plug.Conn.send_file/5`, and `sendfile(2)` doesn't return
  until every byte is on the wire, which for a player consuming a book at
  playback speed is the length of the listening session. A player that pauses,
  seeks, or moves to the next track hangs up mid-transfer, the pending write
  fails with `:closed`, and the exception surfaces at the endpoint. Nothing was
  owed to the client — it left — and no server-side change would prevent it.

  This is only a Sentry-side filter. The exception still propagates and Bandit
  still handles it; we just stop paging ourselves about a listener pressing
  pause.
  """

  @doc """
  Sentry's `:before_send` callback. Returns `nil` to drop the event.
  """
  @spec before_send(Sentry.Event.t()) :: Sentry.Event.t() | nil
  def before_send(%Sentry.Event{original_exception: %Bandit.TransportError{}}), do: nil
  def before_send(%Sentry.Event{} = event), do: event
end
