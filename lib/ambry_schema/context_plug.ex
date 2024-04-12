defmodule AmbrySchema.ContextPlug do
  @moduledoc false

  @behaviour Plug

  @impl Plug
  def init(opts) do
    opts
  end

  @impl Plug
  def call(conn, _opts) do
    context = build_context(conn)
    Absinthe.Plug.put_options(conn, context: context)
  end

  defp build_context(%Plug.Conn{assigns: %{api_user: user, api_user_token: token}}),
    do: %{current_user: user, current_user_token: token}

  defp build_context(_conn), do: %{}
end
