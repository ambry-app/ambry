defmodule Ambry.Deletions.Deletion do
  @moduledoc """
  A record of a deletion.
  """

  use Ecto.Schema

  schema "deletions" do
    field :type, Ecto.Enum,
      values:
        ~w(person author author_person narrator book book_author book_universe series series_book media media_narrator media_translator universe)a

    field :record_id, :integer
    field :deleted_at, :utc_datetime
  end
end
