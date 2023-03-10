defmodule AmbryWeb.Presence do
  @moduledoc false

  use Phoenix.Presence,
    otp_app: :ambry,
    pubsub_server: Ambry.PubSub
end
