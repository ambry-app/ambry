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

    # Billing order. The first narrator is the one a single-narrator display
    # shows, and the order every list of narrators is rendered in.
    field :position, :integer, default: 0

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(media_narrator, attrs) do
    media_narrator
    |> cast(attrs, [:narrator_id, :position])
    |> validate_required(:narrator_id)
  end
end
