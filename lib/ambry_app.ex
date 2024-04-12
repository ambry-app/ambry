defmodule AmbryApp do
  @moduledoc """
  Ambry OTP application.
  """

  use Boundary,
    type: :strict,
    deps: [Ecto.Migrator, Finch, Oban, Phoenix.PubSub, Ambry, AmbryWeb, AmbryScraping],
    exports: [Application]
end
