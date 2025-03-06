defmodule Ambry.PubSub.Message do
  @moduledoc false
  import Ecto.Changeset

  @callback subscribe_topic() :: String.t()

  defmacro __using__(_opts) do
    quote do
      @behaviour Ambry.PubSub.Message

      use Ecto.Schema

      @primary_key false
    end
  end

  def cast(%{"module" => module_string, "message" => attrs}) do
    module = String.to_existing_atom(module_string)

    module
    |> struct()
    |> cast(attrs, module.__schema__(:fields))
    |> apply_changes()
  end
end
