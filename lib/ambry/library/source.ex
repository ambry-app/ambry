defmodule Ambry.Library.Source do
  @moduledoc """
  A watched folder audiobooks arrive from. Read, never written.

  Import always places a source's files into a library root; the source
  carries the default `import_policy` naming how — hardlink, symlink, copy
  or move. The durability question the operator used to answer separately
  ("can these files be trusted to stay?") is answered by the choice itself:
  pick `:symlink` if they'll stay, `:hardlink`/`:copy`/`:move` if they
  might not.

  How organized the folder is doesn't matter and isn't asked: discovery
  measures release boundaries from the tree itself, and a messy downloads
  folder and a meticulously curated collection are the same thing to it.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Ambry.Library.Root

  @import_policies [:hardlink, :symlink, :copy, :move]

  schema "sources" do
    # A *preferred* root, not a binding one: any source may feed any root,
    # and which one an import uses is a per-import decision this only seeds.
    # Pairing each source with a same-filesystem root is what makes
    # hardlinking possible, so complex setups pair them explicitly.
    belongs_to :target_root, Root

    field :name, :string
    field :path, :string
    field :import_policy, Ecto.Enum, values: @import_policies, default: :hardlink
    field :enabled, :boolean, default: true
    field :last_scanned_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  def import_policies, do: @import_policies

  @doc false
  def changeset(source, attrs) do
    source
    |> cast(attrs, [
      :name,
      :path,
      :import_policy,
      :enabled,
      :last_scanned_at,
      :target_root_id
    ])
    |> update_change(:path, &normalize_path/1)
    |> validate_required([:name, :path, :import_policy])
    |> validate_absolute_path()
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
end
