defmodule Ambry.Media.MediaNarrator do
  use Ecto.Schema

  import Ecto.Changeset

  alias Ambry.Media.Media
  alias Ambry.Narrators.Narrator

  schema "media_narrators" do
    belongs_to :media, Media
    belongs_to :narrator, Narrator

    field :delete, :boolean, virtual: true
  end

  @doc false
  def changeset(media_narrator, %{"delete" => "true"}) do
    %{Ecto.Changeset.change(media_narrator, delete: true) | action: :delete}
  end

  def changeset(media_narrator, attrs) do
    media_narrator
    |> cast(attrs, [:narrator_id])
    |> validate_required(:narrator_id)
  end
end
