import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/ambry start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :ambry, AmbryWeb.Endpoint, server: true
end

uploads_path =
  if config_env() == :test do
    Path.join(System.tmp_dir!(), "ambry_test_files")
  else
    System.get_env("UPLOADS_PATH", Path.join(File.cwd!(), "uploads"))
  end

# Ensure folders exist
[uploads_path, "images"] |> Path.join() |> File.mkdir_p!()
[uploads_path, "supplemental"] |> Path.join() |> File.mkdir_p!()
[uploads_path, "media"] |> Path.join() |> File.mkdir_p!()
[uploads_path, "source_media"] |> Path.join() |> File.mkdir_p!()

config :ambry,
  config_env: config_env(),
  uploads_path: uploads_path,
  first_time_setup:
    !(File.exists?(Path.join(uploads_path, "setup.lock")) || config_env() == :test)

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :ambry, Ambry.Repo,
    # ssl: true,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    socket_options: maybe_ipv6

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

  {:ok, %{host: host, port: url_port, scheme: scheme, path: path}} = URI.new(url_string)
  server_port = String.to_integer(System.get_env("PORT") || "80")

  config :ambry, AmbryWeb.Endpoint,
    url: [host: host, port: url_port, scheme: scheme, path: path],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://hexdocs.pm/plug_cowboy/Plug.Cowboy.html
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: server_port
    ],
    secret_key_base: secret_key_base

  config :ambry, :from_address, System.get_env("MAIL_FROM_ADDRESS", "noreply@#{host}")

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :ambry, AmbryWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your endpoint, ensuring
  # no data is ever sent via http, always redirecting to https:
  #
  #     config :ambry, AmbryWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  # ## Configuring the mailer
  #
  with {:ok, provider} <- System.fetch_env("MAIL_PROVIDER") do
    config :swoosh, :api_client, Swoosh.ApiClient.Finch

    case provider do
      "mailjet" ->
        api_key =
          System.get_env("MAILJET_API_KEY") ||
            raise """
            environment variable MAILJET_API_KEY is missing.
            """

        secret =
          System.get_env("MAILJET_SECRET") ||
            raise """
            environment variable MAILJET_SECRET is missing.
            """

        config :ambry, Ambry.Mailer,
          adapter: Swoosh.Adapters.Mailjet,
          api_key: api_key,
          secret: secret
    end
  end

  user_registration_enabled =
    case System.fetch_env("USER_REGISTRATION_ENABLED") do
      {:ok, "yes"} -> true
      {:ok, "no"} -> false
      :error -> false
    end

  config :ambry,
    user_registration_enabled: user_registration_enabled

  with {:ok, url} <- System.fetch_env("MARIONETTE_URL") do
    {:ok, %{scheme: "tcp", host: host, port: port}} = URI.new(url)

    config :ambry, AmbryScraping.Marionette.Connection,
      host: host,
      port: port
  end
end
