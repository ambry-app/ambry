defmodule Ambry.Media.MediaNarrator do
  use Ecto.Schema

  import Ecto.Changeset

  alias Ambry.Media.Media
  alias Ambry.Narrators.Narrator

  schema "media_narrators" do
    belongs_to :media, Media
    belongs_to :narrator, Narrator
  end

  @doc false
  def changeset(media_narrator, attrs) do
    media_narrator
    |> cast(attrs, [:narrator_id])
    |> cast_assoc(:narrator)
    |> validate_narrator()
  end

  defp validate_narrator(changeset) do
    if get_field(changeset, :narrator) do
      changeset
    else
      validate_required(changeset, :narrator_id)
    end
  end
end
