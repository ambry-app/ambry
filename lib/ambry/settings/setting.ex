defmodule Ambry.Settings.Setting do
  @moduledoc """
  One operator-editable setting. A missing row means the default.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:key, :string, []}
  schema "app_settings" do
    field :value, :map, default: %{}

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(setting, attrs) do
    setting
    |> cast(attrs, [:key, :value])
    |> validate_required([:key, :value])
  end
end
