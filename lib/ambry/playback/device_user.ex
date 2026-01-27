defmodule Ambry.Playback.DeviceUser do
  @moduledoc """
  Links devices to users.

  A device can be used by multiple users, and this table tracks each
  user's relationship with a device, including when they last used it.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Ambry.Accounts.User
  alias Ambry.Playback.Device

  @primary_key false

  schema "devices_users" do
    belongs_to :device, Device, type: :binary_id, primary_key: true
    belongs_to :user, User, type: :id, primary_key: true

    field :last_seen_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @doc """
  Creates a changeset for a device-user link.
  """
  def changeset(device_user, attrs) do
    device_user
    |> cast(attrs, [:device_id, :user_id, :last_seen_at])
    |> validate_required([:device_id, :user_id])
    |> default_last_seen_at()
  end

  defp default_last_seen_at(changeset) do
    case get_field(changeset, :last_seen_at) do
      nil ->
        put_change(changeset, :last_seen_at, DateTime.utc_now())

      _ ->
        changeset
    end
  end
end
