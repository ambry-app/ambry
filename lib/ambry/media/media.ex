defmodule Ambry.Media.Media do
  @moduledoc """
  A recording of a book by a narrator.
  """

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
    field :status, Ecto.Enum, values: [:pending, :processing, :error, :ready], default: :pending
    field :abridged, :boolean, default: false

    field :source_path, :string
    field :mpd_path, :string
    field :hls_path, :string
    field :mp4_path, :string

    field :duration, :decimal

    timestamps()
  end

  @doc false
  def changeset(media, attrs, for: :create) do
    media
    |> cast(attrs, [
      :abridged,
      :book_id,
      :full_cast,
      :source_path
    ])
    |> cast_assoc(:media_narrators)
    |> status_based_validation()
  end

  def changeset(media, attrs, for: :update) do
    media
    |> cast(attrs, [
      :abridged,
      :book_id,
      :full_cast
    ])
    |> cast_assoc(:media_narrators)
    |> status_based_validation()
  end

  def changeset(media, attrs, for: :processor_update) do
    media
    |> cast(attrs, [
      :duration,
      :mp4_path,
      :mpd_path,
      :hls_path,
      :status
    ])
    |> status_based_validation()
  end

  defp status_based_validation(changeset) do
    changeset
    # always required
    |> validate_required([
      :book_id,
      :full_cast,
      :status,
      :abridged,
      :source_path
    ])
    |> maybe_validate_paths()
  end

  defp maybe_validate_paths(changeset) do
    if get_field(changeset, :status) == :ready do
      validate_required(changeset, [
        :mpd_path,
        :hls_path,
        :mp4_path
      ])
    else
      changeset
    end
  end
end
