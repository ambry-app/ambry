defmodule Ambry.Playback.Device do
  @moduledoc """
  Represents a client device that produces playback events.

  Devices are identified by client-generated UUIDs and track metadata about
  the client platform. This enables analytics about which devices users
  listen on and helps with debugging sync issues.

  Devices can be shared between users. The `devices_users` table tracks
  which users have used each device.

  ## Device Types
  - `ios`: iOS native app
  - `android`: Android native app
  - `web`: Web browser client
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Ambry.Playback.DeviceUser
  alias Ambry.Playback.PlaybackEvent

  @primary_key {:id, :binary_id, autogenerate: false}
  @foreign_key_type :binary_id

  @device_types [:ios, :android, :web]

  schema "devices" do
    has_many :events, PlaybackEvent
    has_many :device_users, DeviceUser
    has_many :users, through: [:device_users, :user]

    field :type, Ecto.Enum, values: @device_types

    # Device identification
    field :brand, :string
    field :model_name, :string

    # Browser info (web clients)
    field :browser, :string
    field :browser_version, :string

    # OS info
    field :os_name, :string
    field :os_version, :string

    # App info
    field :app_id, :string
    field :app_version, :string
    field :app_build, :string

    timestamps(type: Ambry.Ecto.UtcDateTimeMs)
  end

  @doc """
  Returns the list of valid device types.
  """
  def device_types, do: @device_types

  @doc """
  Creates a changeset for registering a new device.

  Requires a client-generated UUID as the id.
  """
  def changeset(device, attrs) do
    device
    |> cast(attrs, [
      :id,
      :type,
      :brand,
      :model_name,
      :browser,
      :browser_version,
      :os_name,
      :os_version,
      :app_id,
      :app_version,
      :app_build
    ])
    |> validate_required([:id, :type])
  end
end
