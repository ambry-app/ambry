defmodule Ambry.Media.Media do
  use Ecto.Schema

  import Ecto.Changeset

  alias Ambry.Books.Book
  alias Ambry.Media.MediaNarrator
  alias Ambry.Narrators.Narrator

  schema "media" do
    belongs_to :book, Book
    has_many :media_narrators, MediaNarrator
    many_to_many :narrators, Narrator, join_through: "media_narrators"

    field :full_cast, :boolean, default: false
    field :status, Ecto.Enum, values: [:pending, :ready]
    field :abridged, :boolean, default: false

    field :source_path, :string
    field :mpd_path, :string
    field :mp4_path, :string

    timestamps()
  end

  @doc false
  def changeset(media, attrs) do
    media
    |> cast(attrs, [:source_path, :mpd_path, :mp4_path, :full_cast, :abridged, :status, :book_id])
    |> cast_assoc(:media_narrators)
    |> validate_required([:source_path, :status, :book_id])
    |> maybe_validate_paths()
  end

  defp maybe_validate_paths(changeset) do
    if get_field(changeset, :status) == :ready do
      validate_required(changeset, [:mpd_path, :mp4_path])
    else
      changeset
    end
  end
end
