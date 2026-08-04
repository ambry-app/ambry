defmodule Ambry.Library.Location do
  @moduledoc """
  One place on disk that the library is made of.

  A location is either somewhere files arrive from or somewhere files live,
  and `kind` says which:

    * `:downloads` — a messy source folder. Discovery watches it; approval
      brings files into a library root per `import_policy` and the recording
      becomes **managed**.
    * `:external_collection` — an already-organized folder belonging to
      someone else's workflow. Discovery watches it; approval adopts the
      files exactly where they are and the recording becomes **external**.
      Ambry never writes here.
    * `:library_root` — Ambry's own tree, organized by the naming template.
      Managed custody, and the destination `:downloads` imports land in.

  The kinds share a table because the destinations need watching too (files
  hand-placed into the tree have to surface somewhere) and because the
  same-filesystem check that governs hardlinking compares arbitrary pairs of
  locations.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @kinds [:downloads, :external_collection, :library_root]
  @import_policies [:hardlink, :copy, :move]

  schema "library_locations" do
    # Which root a `:downloads` location imports into. Null means "the only
    # A *preferred* output, not a binding one: any input may feed any library
    # root, and which one an import uses is decided per import (see
    # `Ambry.Inbox.Draft.Destination`). This only seeds that choice.
    belongs_to :target_root, __MODULE__

    field :name, :string
    field :path, :string
    field :kind, Ecto.Enum, values: @kinds
    field :import_policy, Ecto.Enum, values: @import_policies
    field :enabled, :boolean, default: true
    field :last_scanned_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  def kinds, do: @kinds
  def import_policies, do: @import_policies

  @doc """
  Whether discovery should look at this location.

  Library roots are watched too — that's how hand-placed files get adopted
  rather than sitting unnoticed in the tree.
  """
  def watched?(%__MODULE__{enabled: enabled}), do: enabled

  @doc """
  Whether Ambry may write, rename or delete inside this location.

  External collections are read-only by definition; that's the whole promise
  of external custody.
  """
  def writable?(%__MODULE__{kind: kind}), do: kind in [:downloads, :library_root]

  @doc false
  def changeset(location, attrs) do
    location
    |> cast(attrs, [
      :name,
      :path,
      :kind,
      :import_policy,
      :enabled,
      :last_scanned_at,
      :target_root_id
    ])
    |> update_change(:path, &normalize_path/1)
    |> validate_required([:name, :path, :kind])
    |> validate_absolute_path()
    |> put_import_policy()
    |> put_target_root()
    |> foreign_key_constraint(:target_root_id)
    |> unique_constraint(:path)
    |> unique_constraint(:name)
  end

  defp normalize_path(nil), do: nil

  defp normalize_path(path) do
    path
    |> String.trim()
    |> String.trim_trailing("/")
    |> case do
      "" -> "/"
      trimmed -> trimmed
    end
  end

  # Every path Ambry stores for a location is absolute. Relative paths would
  # resolve against whatever the release's working directory happens to be,
  # which is not something an operator can reason about from a text field.
  defp validate_absolute_path(changeset) do
    validate_change(changeset, :path, fn :path, path ->
      if Path.type(path) == :absolute,
        do: [],
        else: [path: "must be an absolute path"]
    end)
  end

  # The import policy only means anything for a source folder, so the other
  # kinds don't get to carry a stale one. Downloads default to hardlinking:
  # it's the 1x-storage case this whole phase exists for, and the operator
  # can pick something else deliberately.
  defp put_import_policy(changeset) do
    case get_field(changeset, :kind) do
      :downloads -> update_change_default(changeset, :import_policy, :hardlink)
      _other -> put_change(changeset, :import_policy, nil)
    end
  end

  # Only a downloads folder imports anywhere, so only a downloads folder can
  # name a destination.
  defp put_target_root(changeset) do
    case get_field(changeset, :kind) do
      :downloads -> changeset
      _other -> put_change(changeset, :target_root_id, nil)
    end
  end

  defp update_change_default(changeset, field, default) do
    case get_field(changeset, field) do
      nil -> put_change(changeset, field, default)
      _set -> changeset
    end
  end
end
