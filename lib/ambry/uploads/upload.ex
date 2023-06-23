defmodule Ambry.Uploads.Upload do
  @moduledoc """
  One or more files that have been uploaded
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Ambry.Books.Book
  alias Ambry.Uploads.File

  schema "uploads" do
    embeds_many :files, File, on_replace: :delete
    belongs_to :book, Book, on_replace: :nilify

    field :title, :string

    timestamps()
  end

  @doc false
  def changeset(upload, attrs) do
    upload
    |> cast(attrs, [:title, :book_id])
    |> cast_embed(:files, required: true)
    |> cast_assoc(:book)
  end
end
