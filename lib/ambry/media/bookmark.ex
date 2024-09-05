defmodule Ambry.Media.Bookmark do
  @moduledoc """
  A user defined bookmark for a specific media.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Ambry.Accounts.User
  alias Ambry.Media.Media

  schema "bookmarks" do
    belongs_to :media, Media
    belongs_to :user, User

    field :position, :decimal
    field :label, :string

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(bookmark, attrs) do
    bookmark
    |> cast(attrs, [:position, :label, :media_id, :user_id])
    |> validate_required([:position, :media_id, :user_id])
  end
end
