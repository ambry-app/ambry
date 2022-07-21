defmodule Ambry.Shelves.Shelf do
  @moduledoc """
  A custom user shelf for saving media.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Ambry.Accounts.User
  alias Ambry.Shelves.ShelvedMedia

  schema "shelves" do
    has_many :shelved_media, ShelvedMedia
    has_many :media, through: [:shelved_media, :media]
    belongs_to :user, User

    field :name, :string
    field :order, :integer

    timestamps()
  end

  @doc false
  def changeset(series, attrs) do
    series
    |> cast(attrs, [:name, :order])
    |> validate_required([:name, :order])
    |> foreign_key_constraint(:user, name: "shelves_user_id_fkey")
  end
end
