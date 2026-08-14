defmodule Ambry.Library.Root do
  @moduledoc """
  A folder the library's audio lives in, organized by the naming template.
  Ambry writes here and nowhere else — a root is the only place it serves
  from, so **at least one root is required to import anything**. The inbox
  surfaces `:no_library_root` as "create a library root first" rather than
  offering an import that cannot place.

  Roots are destinations, not sources: they aren't watched, and files only
  arrive in one by being imported into it. An operator with hand-placed
  files points an `Ambry.Library.Source` at them and imports like anything
  else — a `:move` policy organizes them into template shape without
  copying a byte when source and root share a filesystem.

  Images (covers, person photos) never live in a root — they're derived,
  re-fetchable artifacts and keep to Ambry's internal uploads storage
  (`Ambry.Paths`); roots hold audio only.

  Several roots is a first-class arrangement, not a fallback: a hardlink
  can't cross a filesystem, so each disk that receives imports needs a root
  of its own (see `Ambry.Library`).
  """

  use Ecto.Schema

  import Ecto.Changeset

  schema "library_roots" do
    field :name, :string
    field :path, :string

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(root, attrs) do
    root
    |> cast(attrs, [:name, :path])
    |> update_change(:path, &normalize_path/1)
    |> validate_required([:name, :path])
    |> validate_absolute_path()
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
