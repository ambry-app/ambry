defmodule Ambry.Settings do
  @moduledoc """
  Operator-editable settings that aren't about any one record.

  A missing row means the default, so a fresh install needs no seeding.

  ## The direct-play publishing switch

  Direct-play is rolled out client-first: the mobile app has to understand
  tracks-based media *before* the server ever publishes one, or a deployed app
  meets a recording it can't play. The switch is what enforces that ordering —
  it stays off while the server-side machinery ships dark, and the operator
  turns it on only once the fleet has the tracks-capable app build.

  Off doesn't mean nothing works: media can still be scanned, tracks are
  recorded, and everything is visible in the admin UI. It only blocks the last
  step — making a recording that has *only* tracks visible to clients.
  """

  alias Ambry.Repo
  alias Ambry.Settings.Setting

  @direct_play_publishing "direct_play_publishing"

  @doc """
  Whether the server may publish direct-play recordings to clients.

  Defaults to `false` — see the module doc for why the default matters.
  """
  def direct_play_publishing? do
    get_boolean(@direct_play_publishing, false)
  end

  @doc """
  Turns direct-play publishing on or off.
  """
  def set_direct_play_publishing(enabled?) when is_boolean(enabled?) do
    put_boolean(@direct_play_publishing, enabled?)
  end

  defp get_boolean(key, default) do
    case Repo.get(Setting, key) do
      %Setting{value: %{"enabled" => enabled?}} when is_boolean(enabled?) -> enabled?
      _missing_or_malformed -> default
    end
  end

  defp put_boolean(key, enabled?) do
    %Setting{}
    |> Setting.changeset(%{key: key, value: %{"enabled" => enabled?}})
    |> Repo.insert(on_conflict: {:replace, [:value, :updated_at]}, conflict_target: :key)
  end
end
