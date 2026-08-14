defmodule Ambry.People.Person do
  @moduledoc """
  A person with a bio.

  Can be (multiple) authors and narrators. (Not used for users).
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Ambry.Paths
  alias Ambry.People.AuthorPerson
  alias Ambry.People.Narrator
  alias Ambry.Provenance
  alias Ambry.Thumbnails

  # provider-fillable scalar fields tracked by field-level provenance
  @provenance_fields [:name, :description, :image_path]

  schema "people" do
    has_many :author_people, AuthorPerson, on_replace: :delete
    has_many :authors, through: [:author_people, :author]
    has_many :narrators, Narrator, on_replace: :delete

    embeds_one :thumbnails, Thumbnails, on_replace: :delete

    field :name, :string
    field :description, :string
    field :image_path, :string

    field :field_provenance, :map, default: %{}

    timestamps(type: :utc_datetime)
  end

  def provenance_fields, do: @provenance_fields

  @doc false
  def changeset(person, attrs, opts \\ []) do
    person
    |> cast(attrs, [:name, :description, :image_path])
    |> cast_assoc(:author_people,
      sort_param: :author_people_sort,
      drop_param: :author_people_drop
    )
    |> cast_assoc(:narrators,
      sort_param: :narrators_sort,
      drop_param: :narrators_drop
    )
    |> cast_embed(:thumbnails)
    |> maybe_clear_thumbnails()
    |> validate_required([:name])
    |> validate_image_path()
    |> foreign_key_constraint(:narrator, name: "media_narrators_narrator_id_fkey")
    |> check_constraint(:thumbnails, name: "thumbnails_original_match_constraint")
    |> Provenance.track_changes(@provenance_fields, opts[:provenance] || %{})
  end

  # if the image_path changes, clear the thumbnails embed
  defp maybe_clear_thumbnails(changeset) do
    case fetch_change(changeset, :image_path) do
      {:ok, _new_path} -> put_embed(changeset, :thumbnails, nil)
      _ -> changeset
    end
  end

  defp validate_image_path(changeset) do
    validate_change(changeset, :image_path, fn :image_path, path ->
      case path do
        "/uploads/" <> _ = path ->
          if path |> Paths.web_to_disk() |> File.exists?() do
            []
          else
            [image_path: "file does not exist"]
          end

        nil ->
          []

        _ ->
          [image_path: "must begin with /uploads/"]
      end
    end)
  end
end
