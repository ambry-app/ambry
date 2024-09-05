defmodule Ambry.Accounts.UserFlat do
  @moduledoc """
  A flattened view of users.
  """

  use Ambry.Repo.FlatSchema

  schema "users_flat" do
    field :email, :string
    field :admin, :boolean
    field :confirmed, :boolean
    field :media_in_progress, :integer
    field :media_finished, :integer
    field :last_login_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  def filter(query, :search, search_string) do
    search_string = "%#{search_string}%"

    from p in query, where: ilike(p.email, ^search_string)
  end

  def filter(query, :admin, admin?), do: from(p in query, where: [admin: ^admin?])

  def filter(query, :confirmed, confirmed?), do: from(p in query, where: [confirmed: ^confirmed?])
end
