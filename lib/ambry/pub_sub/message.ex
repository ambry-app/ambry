defmodule Ambry.PubSub.Message do
  @moduledoc """
  A struct for pubsub messages
  """

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key false
  @derive Jason.Encoder

  embedded_schema do
    field :id, :integer
    field :type, Ecto.Enum, values: [:person]
    field :action, Ecto.Enum, values: [:created, :updated, :deleted]
    field :meta, :map
  end

  def encode(%__MODULE__{} = message) do
    Jason.encode!(message)
  end

  def decode(message) do
    attrs = Jason.decode!(message)

    %__MODULE__{}
    |> cast(attrs, [:id, :type, :action, :meta])
    |> apply_changes()
  end
end

defmodule Ambry.PubSub.MessageNew do
  @moduledoc false
  import Ecto.Changeset

  @callback subscribe_topic() :: String.t()

  defmacro __using__(_opts) do
    quote do
      @behaviour Ambry.PubSub.MessageNew

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
