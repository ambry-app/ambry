defmodule Ambry.SentryFilterTest do
  use ExUnit.Case, async: true

  alias Ambry.SentryFilter

  describe "before_send/1" do
    test "drops a transport error raised by a client hanging up mid-send" do
      event =
        Sentry.Event.create_event(
          exception: %Bandit.TransportError{
            message: "Unrecoverable error: closed",
            error: :closed
          }
        )

      assert SentryFilter.before_send(event) == nil
    end

    test "keeps everything else" do
      event = Sentry.Event.create_event(exception: %RuntimeError{message: "boom"})

      assert SentryFilter.before_send(event) == event
    end
  end
end
