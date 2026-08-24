defmodule Ambry.Settings do
  @moduledoc """
  Operator-editable settings that aren't about any one record. A missing row
  means the default, so a fresh install needs no seeding.

  **The direct-play publishing switch** enforces a client-first rollout: a
  deployed app has to understand tracks-based media before the server
  publishes one. Off, media can still be scanned, tracks are recorded and
  everything is visible in the admin; only the last step is blocked, making a
  tracks-only recording visible to clients.

  """

  alias Ambry.Library.NamingTemplate
  alias Ambry.Repo
  alias Ambry.Settings.Setting

  @direct_play_publishing "direct_play_publishing"
  @library_naming_template "library_naming_template"

  @doc """
  The folder template managed recordings are organized into. See
  `Ambry.Library.NamingTemplate` for the tokens.
  """
  def library_naming_template do
    case Repo.get(Setting, @library_naming_template) do
      %Setting{value: %{"template" => template}} when is_binary(template) -> template
      _missing_or_malformed -> NamingTemplate.default_template()
    end
  end

  @doc """
  Sets the folder template, refusing one that can't produce a usable path.
  """
  def set_library_naming_template(template) when is_binary(template) do
    with :ok <- NamingTemplate.validate(template) do
      %Setting{}
      |> Setting.changeset(%{key: @library_naming_template, value: %{"template" => template}})
      |> Repo.insert(on_conflict: {:replace, [:value, :updated_at]}, conflict_target: :key)
    end
  end

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
