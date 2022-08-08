defmodule AmbrySchema.AuthMiddleware do
  @moduledoc false

  @behaviour Absinthe.Middleware

  alias Ambry.Accounts.User

  @impl Absinthe.Middleware
  def call(%{context: %{current_user: %User{}}} = resolution, _opts) do
    resolution
  end

  def call(resolution, _opts) do
    Absinthe.Resolution.put_result(resolution, {:error, "unauthorized"})
  end
end
