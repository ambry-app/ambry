defmodule Ambry.PubSub.Message do
  @moduledoc """
  A struct for pubsub messages
  """

  defstruct [:type, :action, :id, :meta]
end
