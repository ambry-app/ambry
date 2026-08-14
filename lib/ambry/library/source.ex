defmodule Ambry.Library.Source do
  @moduledoc """
  A watched folder audiobooks arrive from.

  A source carries exactly one promise, made by the operator: whether these
  files can be trusted to stay. `on_import` names what import does about it:

    * `:bring_in` — the folder belongs to something that may delete from it
      (a download client, usually), so import protects the library by
      placing its own copy of the bytes into a library root, per
      `import_policy`, and the recording becomes **managed**.
    * `:leave_in_place` — the files are staying put, so import references
      them exactly where they are and the recording becomes **external**.
      Ambry never writes here.

  How organized the folder is doesn't matter and isn't asked: discovery
  measures release boundaries from the tree itself, and a messy downloads
  folder and a meticulously curated collection are the same thing to it.
  The one distinction that changes behavior is the durability promise.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Ambry.Library.Root

  @on_import [:bring_in, :leave_in_place]
  @import_policies [:hardlink, :symlink, :copy, :move]

  schema "sources" do
    # A *preferred* root, not a binding one: any source may feed any root,
    # and which one an import uses is a per-import decision this only seeds.
    # Pairing each bring-in source with a same-filesystem root is what makes
    # hardlinking possible, so complex setups pair them explicitly.
    belongs_to :target_root, Root

    field :name, :string
    field :path, :string
    field :on_import, Ecto.Enum, values: @on_import
    field :import_policy, Ecto.Enum, values: @import_policies
    field :enabled, :boolean, default: true
    field :last_scanned_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  def on_import_choices, do: @on_import
  def import_policies, do: @import_policies

  @doc false
  def changeset(source, attrs) do
    source
    |> cast(attrs, [
      :name,
      :path,
      :on_import,
      :import_policy,
      :enabled,
      :last_scanned_at,
      :target_root_id
    ])
    |> update_change(:path, &normalize_path/1)
    |> validate_required([:name, :path, :on_import])
    |> validate_absolute_path()
    |> put_import_policy()
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

  # Every path Ambry stores is absolute. Relative paths would resolve against
  # whatever the release's working directory happens to be, which is not
  # something an operator can reason about from a text field.
  defp validate_absolute_path(changeset) do
    validate_change(changeset, :path, fn :path, path ->
      if Path.type(path) == :absolute,
        do: [],
        else: [path: "must be an absolute path"]
    end)
  end

  # The policy and the preferred root only mean anything when import brings
  # files in, so a leave-in-place source doesn't get to carry stale ones.
  # Bring-in defaults to hardlinking: it's the 1x-storage case this whole
  # phase exists for, and the operator can pick something else deliberately.
  defp put_import_policy(changeset) do
    case get_field(changeset, :on_import) do
      :bring_in ->
        update_change_default(changeset, :import_policy, :hardlink)

      _leave_in_place ->
        changeset
        |> put_change(:import_policy, nil)
        |> put_change(:target_root_id, nil)
    end
  end

  defp update_change_default(changeset, field, default) do
    case get_field(changeset, field) do
      nil -> put_change(changeset, field, default)
      _set -> changeset
    end
  end
end
