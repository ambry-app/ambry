defmodule AmbryWeb.Presence do
  use Phoenix.Presence,
    otp_app: :ambry,
    pubsub_server: Ambry.PubSub
end
