defmodule AmbryWeb.Admin.Components.AdminNav do
  @moduledoc """
  Renders the admin navigation bar.
  """

  use AmbryWeb, :component

  alias AmbryWeb.Endpoint
  alias Surface.Components.LiveRedirect

  def render(assigns) do
    ~F"""
    <div class="p-2 mb-4">
      <div class="flex divide-x divide-gray-200 text-lime-500">
        <LiveRedirect to={Routes.admin_home_index_path(Endpoint, :index)} class="px-2 hover:underline">
          Admin Home
        </LiveRedirect>

        <LiveRedirect to={Routes.admin_person_index_path(Endpoint, :index)} class="px-2 hover:underline">
          People
        </LiveRedirect>

        <LiveRedirect to={Routes.admin_book_index_path(Endpoint, :index)} class="px-2 hover:underline">
          Books
        </LiveRedirect>

        <LiveRedirect to={Routes.admin_series_index_path(Endpoint, :index)} class="px-2 hover:underline">
          Series
        </LiveRedirect>

        <LiveRedirect to={Routes.admin_media_index_path(Endpoint, :index)} class="px-2 hover:underline">
          Media
        </LiveRedirect>

        <LiveRedirect to={Routes.admin_audit_index_path(Endpoint, :index)} class="px-2 hover:underline">
          Audit
        </LiveRedirect>

        <LiveRedirect to={Routes.live_dashboard_path(Endpoint, :home)} class="px-2 hover:underline">
          Phoenix Dashboard
        </LiveRedirect>
      </div>
    </div>
    """
  end
end
