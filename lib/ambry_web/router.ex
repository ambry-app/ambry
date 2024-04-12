defmodule AmbryWeb.Router do
  use AmbryWeb, :router

  import AmbryWeb.UserAuth
  import Phoenix.LiveDashboard.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {AmbryWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_user
    plug AmbryWeb.Plugs.FirstTimeSetup
  end

  pipeline :uploads do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_current_user
    plug :fetch_api_user
    plug :require_any_authenticated_user

    # Serve static user uploaded media
    plug Plug.Static,
      at: "/uploads",
      from: {Ambry.Paths, :uploads_folder_disk_path, []},
      gzip: false,
      only: ~w(media)
  end

  pipeline :downloads do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_current_user
    plug :fetch_api_user
    plug :require_any_authenticated_user
  end

  pipeline :gql do
    plug :accepts, ["json", "graphql"]
    plug :fetch_api_user
    plug AmbrySchema.ContextPlug
  end

  scope "/uploads" do
    pipe_through :uploads

    get "/*path", AmbryWeb.FallbackController, :index
  end

  scope "/" do
    pipe_through :downloads

    get "/download/media/:media_id/:file_id/*rest", AmbryWeb.DownloadController, :download_media
  end

  scope "/gql" do
    pipe_through :gql

    forward "/", Absinthe.Plug.GraphiQL, schema: AmbrySchema, interface: :playground
  end

  pipeline :admin do
    plug :put_root_layout, html: {AmbryWeb.Admin.Layouts, :root}
  end

  # Enable GraphQL Voyager and Swoosh mailbox preview in development
  if Application.compile_env(:ambry, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).

    scope "/dev" do
      pipe_through :browser

      forward "/mailbox", Plug.Swoosh.MailboxPreview
      forward "/voyager", AmbryWeb.Plugs.Voyager
    end
  end

  ## Preview routes

  pipeline :preview do
    plug :put_root_layout, html: {AmbryWeb.Preview.Layouts, :root}
    plug :put_layout, html: {AmbryWeb.Preview.Layouts, :app}
    plug :redirect_if_user_is_authenticated
  end

  scope "/preview", AmbryWeb.Preview do
    pipe_through [:browser, :preview]

    get "/books/:id", BookController, :show
  end

  ## Authentication routes

  scope "/", AmbryWeb do
    pipe_through [:browser, :redirect_if_user_is_authenticated]

    live_session :redirect_if_user_is_authenticated,
      on_mount: [{AmbryWeb.UserAuth, :redirect_if_user_is_authenticated}] do
      live "/users/register", UserRegistrationLive, :new
      live "/users/log_in", UserLoginLive, :new
      live "/users/reset_password", UserForgotPasswordLive, :new
      live "/users/reset_password/:token", UserResetPasswordLive, :edit
    end

    post "/users/log_in", UserSessionController, :create
  end

  scope "/", AmbryWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :require_authenticated_user,
      on_mount: [
        {AmbryWeb.UserAuth, :ensure_authenticated},
        AmbryWeb.NavHooks,
        AmbryWeb.PlayerStateHooks
      ] do
      live "/", NowPlayingLive
      live "/library", LibraryLive
      live "/shelf", ShelfLive
      live "/people/:id", PersonLive
      live "/authors/:id", AuthorOrNarratorLive, :author
      live "/narrators/:id", AuthorOrNarratorLive, :narrator
      live "/series/:id", SeriesLive
      live "/books/:id", BookLive
      live "/search/:query", SearchLive

      live "/users/settings", UserSettingsLive, :edit
      live "/users/settings/confirm_email/:token", UserSettingsLive, :confirm_email
    end
  end

  scope "/", AmbryWeb do
    pipe_through :browser

    delete "/users/log_out", UserSessionController, :delete

    live_session :current_user,
      on_mount: [{AmbryWeb.UserAuth, :mount_current_user}] do
      live "/users/confirm/:token", UserConfirmationLive, :edit
      live "/users/confirm", UserConfirmationInstructionsLive, :new
    end
  end

  scope "/first_time_setup", AmbryWeb.FirstTimeSetup do
    pipe_through :browser

    live_session :setup, layout: {AmbryWeb.Layouts, :auth} do
      live "/", SetupLive, :index
    end
  end

  scope "/admin", AmbryWeb.Admin, as: :admin do
    pipe_through [:browser, :require_authenticated_user, :require_admin, :admin]

    live_session :admin,
      on_mount: [
        {AmbryWeb.UserAuth, :ensure_authenticated},
        {AmbryWeb.Admin.Auth, :ensure_mounted_admin_user},
        AmbryWeb.Admin.NavHooks
      ] do
      live "/", HomeLive.Index, :index

      live "/people", PersonLive.Index
      live "/people/new", PersonLive.Form, :new
      live "/people/:id/edit", PersonLive.Form, :edit

      live "/books", BookLive.Index
      live "/books/new", BookLive.Form, :new
      live "/books/:id/edit", BookLive.Form, :edit

      live "/series", SeriesLive.Index
      live "/series/new", SeriesLive.Form, :new
      live "/series/:id/edit", SeriesLive.Form, :edit

      live "/media", MediaLive.Index
      live "/media/new", MediaLive.Form, :new
      live "/media/:id/edit", MediaLive.Form, :edit
      live "/media/:id/chapters", MediaLive.Chapters

      live "/users", UserLive.Index

      live "/audit", AuditLive.Index, :index
    end

    live_dashboard "/dashboard", metrics: AmbryWeb.Telemetry
  end
end
