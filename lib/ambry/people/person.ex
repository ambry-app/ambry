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
  alias Ambry.Thumbnails

  schema "people" do
    has_many :author_people, AuthorPerson, on_replace: :delete
    has_many :authors, through: [:author_people, :author]
    has_many :narrators, Narrator, on_replace: :delete

    embeds_one :thumbnails, Thumbnails, on_replace: :delete

    field :name, :string
    field :description, :string
    field :image_path, :string

    # form-only: staging input for linking an existing author, see
    # AmbryWeb.Admin.PersonLive.Form
    field :link_author_id, :integer, virtual: true

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(person, attrs) do
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
