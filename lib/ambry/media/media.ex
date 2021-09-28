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

    field :path, :string
    field :full_cast, :boolean, default: false
    field :status, Ecto.Enum, values: [:pending, :ready]
    field :abridged, :boolean, default: false

    timestamps()
  end

  @doc false
  def changeset(media, attrs) do
    media
    |> cast(attrs, [:path, :full_cast, :abridged, :status, :book_id])
    |> cast_assoc(:media_narrators)
    |> validate_required([:path, :status, :book_id])
  end
end
