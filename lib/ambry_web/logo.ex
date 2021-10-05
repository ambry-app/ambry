defmodule AmbryWeb.Logo do
  @moduledoc """
  Helpers for inserting the Ambry logo in various ways.
  """

  use Phoenix.Component

  alias AmbryWeb.Router.Helpers, as: Routes

  def logo_with_tagline(assigns) do
    ~H"""
    <h1 class="text-center">
      <img class="mx-auto" style="max-height: 128px;" alt="Ambry" src={Routes.static_path(@conn, "/images/logo_256x1056.svg")}>
      <span class="font-semibold text-gray-500">Personal Audiobook Streaming</span>
    </h1>
    """
  end
end
