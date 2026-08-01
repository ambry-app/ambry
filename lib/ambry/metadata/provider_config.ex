defmodule Ambry.Metadata.ProviderConfig do
  @moduledoc """
  Operator-editable settings for one metadata provider.

  A missing row means "all defaults" — providers work zero-config out of the
  box; rows exist only where the operator changed something.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:provider_id, :string, []}
  schema "metadata_provider_configs" do
    field :enabled, :boolean, default: true
    field :priority, :integer
    field :config, :map, default: %{}

    timestamps(type: :utc_datetime)
  end

  def changeset(provider_config, attrs) do
    provider_config
    |> cast(attrs, [:provider_id, :enabled, :priority, :config])
    |> validate_required([:provider_id, :enabled])
  end
end
