defmodule AmbryWeb.Admin.Components.AdminNav do
  @moduledoc """
  Renders the admin navigation bar.
  """

  use AmbryWeb, :component

  alias Surface.Components.LiveRedirect

  def render(assigns) do
    ~F"""
    <div class="p-2 mb-4">
      <div class="flex divide-x divide-gray-200 text-lime-500">
        <LiveRedirect to={Routes.admin_person_index_path(@socket, :index)} class="px-2">
          People
        </LiveRedirect>

        <LiveRedirect to={Routes.admin_book_index_path(@socket, :index)} class="px-2">
          Books
        </LiveRedirect>

        <LiveRedirect to={Routes.admin_series_index_path(@socket, :index)} class="px-2">
          Series
        </LiveRedirect>

        <LiveRedirect to={Routes.admin_media_index_path(@socket, :index)} class="px-2">
          Media
        </LiveRedirect>

        <LiveRedirect to={Routes.admin_audit_index_path(@socket, :index)} class="px-2">
          Audit
        </LiveRedirect>
      </div>
    </div>
    """
  end
end
