import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.

uploads_path =
  if config_env() == :test do
    Path.join(System.tmp_dir!(), "ambry_test_files")
  else
    System.get_env("UPLOADS_PATH", Path.join(File.cwd!(), "uploads"))
  end

# Ensure folders exist
[uploads_path, "images"] |> Path.join() |> File.mkdir_p!()
[uploads_path, "media"] |> Path.join() |> File.mkdir_p!()
[uploads_path, "source_media"] |> Path.join() |> File.mkdir_p!()

config :ambry,
  config_env: config_env(),
  uploads_path: uploads_path,
  first_time_setup:
    !(File.exists?(Path.join(uploads_path, "setup.lock")) || config_env() == :test)

# The block below contains prod specific runtime configuration.
if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  config :ambry, Ambry.Repo,
    # ssl: true,
    # socket_options: [:inet6],
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE", "10"))

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  url_string =
    System.get_env("BASE_URL") ||
      raise """
      environment variable BASE_URL is missing.
      """

  %{host: host, port: port} = URI.parse(url_string)

  config :ambry, AmbryWeb.Endpoint,
    url: [host: host, port: port],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://hexdocs.pm/plug_cowboy/Plug.Cowboy.html
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: String.to_integer(System.get_env("PORT", "80"))
    ],
    secret_key_base: secret_key_base

  # ## Using releases
  #
  # If you are doing OTP releases, you need to instruct Phoenix
  # to start each relevant endpoint:
  #
  config :ambry, AmbryWeb.Endpoint, server: true
  #
  # Then you can assemble a release by calling `mix release`.
  # See `mix help release` for more information.

  config :ambry, :from_address, System.get_env("MAIL_FROM_ADDRESS", "noreply@#{host}")

  # ## Configuring the mailer
  #
  case System.get_env("MAIL_PROVIDER") do
    nil ->
      # no mail provider configured
      :noop

    provider ->
      config :swoosh, :api_client, Swoosh.ApiClient.Finch

      case provider do
        "mailjet" ->
          config :ambry, Ambry.Mailer,
            adapter: Swoosh.Adapters.Mailjet,
            api_key: System.fetch_env!("MAILJET_API_KEY"),
            secret: System.fetch_env!("MAILJET_SECRET")
      end
  end

  user_registration_enabled =
    case System.get_env("USER_REGISTRATION_ENABLED", "no") do
      "yes" -> true
      "no" -> false
      _ -> false
    end

  config :ambry,
    user_registration_enabled: user_registration_enabled
end
