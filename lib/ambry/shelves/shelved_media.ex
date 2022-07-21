defmodule Ambry.Shelves.ShelvedMedia do
  @moduledoc """
  Join table for media to shelves.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Ambry.Media.Media
  alias Ambry.Shelves.Shelf

  schema "media_shelves" do
    belongs_to :shelf, Shelf
    belongs_to :media, Media

    field :order, :integer
    field :delete, :boolean, virtual: true
  end

  @doc false
  def changeset(shelved_media, attrs) do
    shelved_media
    |> cast(attrs, [:media_id, :shelf_id, :delete])
    |> validate_required([:media_id, :shelf_id])
    |> maybe_apply_delete()
  end

  defp maybe_apply_delete(changeset) do
    if Ecto.Changeset.get_change(changeset, :delete, false) do
      %{changeset | action: :delete}
    else
      changeset
    end
  end
end
