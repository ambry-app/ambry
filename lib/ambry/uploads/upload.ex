defmodule Ambry.Uploads.Upload do
  @moduledoc """
  One or more files that have been uploaded
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Ambry.Books.Book
  alias Ambry.Media.Media.Chapter
  alias Ambry.Narrators.Narrator
  alias Ambry.SupplementalFile
  alias Ambry.Uploads.File
  alias Ambry.Uploads.UploadNarrator

  @statuses [:pending, :processing, :error, :ready]

  schema "uploads" do
    belongs_to :book, Book

    has_many :upload_narrators, UploadNarrator
    many_to_many :narrators, Narrator, join_through: "upload_narrators"

    embeds_many :source_files, File, on_replace: :delete
    embeds_many :chapters, Chapter, on_replace: :delete
    embeds_many :supplemental_files, SupplementalFile, on_replace: :delete

    field :title, :string

    field :status, Ecto.Enum, values: @statuses, default: :pending
    field :full_cast, :boolean, default: false
    field :abridged, :boolean, default: false
    field :published, :date
    field :published_format, Ecto.Enum, values: [:full, :year_month, :year]
    field :notes, :string

    field :mpd_path, :string
    field :hls_path, :string
    field :mp4_path, :string

    timestamps()
  end

  @doc false
  def changeset(upload, attrs) do
    upload
    |> cast(attrs, [:title, :book_id])
    |> cast_embed(:source_files, required: true)
    |> cast_assoc(:book)
    |> cast_assoc(:upload_narrators)
  end
end
