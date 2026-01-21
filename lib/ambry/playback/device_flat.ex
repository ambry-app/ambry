defmodule Ambry.Playback.DeviceFlat do
  @moduledoc """
  A flattened view of devices.
  """

  use Ambry.Repo.FlatSchema

  @primary_key {:id, :binary_id, autogenerate: false}

  schema "devices_flat" do
    field :user_id, :integer
    field :type, Ecto.Enum, values: [:ios, :android, :web]
    field :brand, :string
    field :model_name, :string
    field :browser, :string
    field :browser_version, :string
    field :os_name, :string
    field :os_version, :string
    field :app_id, :string
    field :app_version, :string
    field :app_build, :string
    field :last_seen_at, Ambry.Ecto.UtcDateTimeMs
    field :event_count, :integer

    timestamps(type: Ambry.Ecto.UtcDateTimeMs)
  end

  def filter(query, :user_id, user_id) do
    from d in query, where: d.user_id == ^user_id
  end

  def filter(query, :search, search_string) do
    search_string = "%#{search_string}%"

    from d in query,
      where:
        ilike(d.brand, ^search_string) or
          ilike(d.model_name, ^search_string) or
          ilike(d.os_name, ^search_string) or
          ilike(d.browser, ^search_string) or
          ilike(d.app_id, ^search_string)
  end
end
