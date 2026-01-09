defmodule Ambry.Playback.Device do
  @moduledoc """
  Represents a client device that produces playback events.

  Devices are identified by client-generated UUIDs and track metadata about
  the client platform. This enables analytics about which devices users
  listen on and helps with debugging sync issues.

  ## Device Types
  - `ios`: iOS native app
  - `android`: Android native app
  - `web`: Web browser client
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Ambry.Accounts.User
  alias Ambry.Playback.PlaybackEvent

  @primary_key {:id, :binary_id, autogenerate: false}
  @foreign_key_type :binary_id

  @device_types [:ios, :android, :web]

  schema "devices" do
    belongs_to :user, User, type: :id

    has_many :events, PlaybackEvent

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

    field :last_seen_at, Ambry.Ecto.UtcDateTimeMs

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
      :user_id,
      :type,
      :brand,
      :model_name,
      :browser,
      :browser_version,
      :os_name,
      :os_version,
      :last_seen_at
    ])
    |> validate_required([:id, :user_id, :type])
    |> default_last_seen_at()
  end

  @doc """
  Creates a changeset for updating last_seen_at.
  """
  def touch_changeset(device) do
    device
    |> change(last_seen_at: DateTime.utc_now() |> DateTime.truncate(:millisecond))
  end

  defp default_last_seen_at(changeset) do
    case get_field(changeset, :last_seen_at) do
      nil ->
        put_change(changeset, :last_seen_at, DateTime.utc_now() |> DateTime.truncate(:millisecond))

      _ ->
        changeset
    end
  end
end
