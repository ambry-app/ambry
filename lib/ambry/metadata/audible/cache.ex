defmodule Ambry.Metadata.Audible.Cache do
  @moduledoc """
  A cached Audible scraper response
  """

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:key, :string, []}

  schema "audible_cache" do
    field :value, :binary

    timestamps(updated_at: false)
  end

  @doc false
  def changeset(cache, attrs) do
    cache
    |> cast(attrs, [:key, :value])
    |> validate_required([:key, :value])
  end
end
