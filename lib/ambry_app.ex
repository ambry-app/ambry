defmodule AmbryApp do
  @moduledoc """
  Ambry OTP application.
  """

  use Boundary,
    type: :strict,
    deps: [
      # External
      Ecto.Migrator,
      Finch,
      Oban,
      Phoenix.PubSub,
      # Internal
      Ambry,
      AmbryScraping,
      AmbryWeb
    ],
    exports: [Application]
end
