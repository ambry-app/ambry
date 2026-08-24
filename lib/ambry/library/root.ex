defmodule Ambry.Library.Root do
  @moduledoc """
  A folder the library's audio lives in, organized by the naming template.
  Ambry writes here and nowhere else, so at least one root is required to
  import anything.

  Roots are destinations, not sources: they aren't watched, and files only
  arrive in one by being imported. Images are derived artifacts and keep to
  Ambry's own uploads storage (`Ambry.Paths`); roots hold audio only.

  A hardlink can't cross a filesystem, so each disk that receives imports
  needs a root of its own.
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

  # Absolute only: a relative path would resolve against the release's
  # working directory, which no operator can reason about from a text field.
  defp validate_absolute_path(changeset) do
    validate_change(changeset, :path, fn :path, path ->
      if Path.type(path) == :absolute,
        do: [],
        else: [path: "must be an absolute path"]
    end)
  end
end
