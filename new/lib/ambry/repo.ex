defmodule Ambry.Repo do
  @moduledoc false

  use Ecto.Repo,
    otp_app: :ambry,
    adapter: Ecto.Adapters.Postgres
end
