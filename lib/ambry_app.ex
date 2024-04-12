defmodule AmbryApp do
  @moduledoc """
  Ambry OTP application.
  """

  use Boundary, deps: [Ambry, AmbryWeb, AmbryScraping], exports: [Application]
end
