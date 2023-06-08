defmodule Ambry.Repo do
  @moduledoc false

  use Ecto.Repo,
    otp_app: :ambry,
    adapter: Ecto.Adapters.Postgres

  def fetch(queryable, id, opts \\ []) do
    case get(queryable, id, opts) do
      nil -> {:error, :not_found}
      result -> {:ok, result}
    end
  end

  def fetch_one(queryable, opts \\ []) do
    case one(queryable, opts) do
      nil -> {:error, :not_found}
      result -> {:ok, result}
    end
  end
end
