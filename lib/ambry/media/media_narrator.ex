defmodule Ambry.Media.MediaNarrator do
  @moduledoc """
  Join table between media and narrators.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Ambry.Media.Media
  alias Ambry.People.Narrator

  schema "media_narrators" do
    belongs_to :media, Media
    belongs_to :narrator, Narrator

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(media_narrator, attrs) do
    media_narrator
    |> cast(attrs, [:narrator_id])
    |> validate_required(:narrator_id)
  end
end
