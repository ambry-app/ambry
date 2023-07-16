defmodule AmbryWeb do
  @moduledoc """
  The entrypoint for defining your web interface, such
  as controllers, components, channels, and so on.

  This can be used in your application as:

      use AmbryWeb, :controller
      use AmbryWeb, :html

  The definitions below will be executed for every controller,
  component, etc, so keep them short and clean, focused
  on imports, uses and aliases.

  Do NOT define functions inside the quoted expressions
  below. Instead, define additional modules and import
  those modules here.
  """

  def static_paths, do: ~w(assets favicon.svg favicon.png favicon-32x32.png favicon-96x96.png robots.txt)

  def router do
    quote do
      use Phoenix.Router, helpers: false

      # Import common connection and controller functions to use in pipelines
      import Phoenix.Controller
      import Phoenix.LiveView.Router
      import Plug.Conn
    end
  end

  def channel do
    quote do
      use Phoenix.Channel
    end
  end

  def controller do
    quote do
      use Phoenix.Controller,
        formats: [:html, :json],
        layouts: [html: AmbryWeb.Layouts]

      import AmbryWeb.Gettext
      import Plug.Conn

      unquote(verified_routes())
    end
  end

  def live_view do
    quote do
      use Phoenix.LiveView,
        layout: {AmbryWeb.Layouts, :app},
        container: {:div, class: "contents"}

      unquote(html_helpers())
    end
  end

  def auth_live_view do
    quote do
      use Phoenix.LiveView, layout: {AmbryWeb.Layouts, :auth}

      unquote(html_helpers())
    end
  end

  def admin_live_view do
    quote do
      use Phoenix.LiveView, layout: {AmbryWeb.Admin.Layouts, :app}

      import AmbryWeb.Admin.Components

      unquote(html_helpers())
    end
  end

  def live_component do
    quote do
      use Phoenix.LiveComponent

      unquote(html_helpers())
    end
  end

  def html do
    quote do
      use Phoenix.Component

      # Import convenience functions from controllers
      import Phoenix.Controller,
        only: [get_csrf_token: 0, view_module: 1, view_template: 1]

      # Include general helpers for rendering HTML
      unquote(html_helpers())
    end
  end

  defp html_helpers do
    quote do
      # HTML escaping functionality
      # Core UI components and translation
      import AmbryWeb.CoreComponents
      import AmbryWeb.Gettext
      import Phoenix.HTML

      # Shortcut for generating JS commands
      alias FontAwesome.LiveView, as: FA
      alias Phoenix.LiveView.JS

      # FontAwesome icons

      # Routes generation with the ~p sigil
      unquote(verified_routes())
    end
  end

  def verified_routes do
    quote do
      use Phoenix.VerifiedRoutes,
        endpoint: AmbryWeb.Endpoint,
        router: AmbryWeb.Router,
        statics: AmbryWeb.static_paths()
    end
  end

  @doc """
  When used, dispatch to the appropriate controller/view/etc.
  """
  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
