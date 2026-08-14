defmodule Ambry.Library.Source do
  @moduledoc """
  A watched folder audiobooks arrive from. Read, never written.

  A source is a path and nothing else — where to look, and whether to keep
  looking. What happens to what it finds is decided at import, because that
  is where the question can be answered.

  ## Why placement isn't configured here

  Import places a source's files into a library root by hardlinking,
  symlinking, copying or moving them, and this used to carry a default
  naming which. Two things were wrong with that. Whether a hardlink is even
  *possible* depends on the source and the root sharing a filesystem, which
  one end cannot know — the same downloads folder may hardlink into one root
  and have to copy into another on a different disk. And the field was never
  binding: every import could change it, which makes it a default rather
  than a setting, and a default that is overridden half the time is better
  learned than typed.

  So the pairing remembers instead (`Ambry.Library.ImportPreference`), and
  the source's preferred root went the same way: the root it most recently
  imported into is the one it proposes next.

  How organized the folder is doesn't matter and isn't asked: discovery
  measures release boundaries from the tree itself, and a messy downloads
  folder and a meticulously curated collection are the same thing to it.
  """

  use Ecto.Schema

  import Ecto.Changeset

  schema "sources" do
    field :name, :string
    field :path, :string
    field :enabled, :boolean, default: true
    field :last_scanned_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(source, attrs) do
    source
    |> cast(attrs, [:name, :path, :enabled, :last_scanned_at])
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
