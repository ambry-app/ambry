defmodule Ambry.Repo do
  use Ecto.Repo,
    otp_app: :ambry,
    adapter: Ecto.Adapters.Postgres
end
