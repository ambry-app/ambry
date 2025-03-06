defmodule Ambry.Media.Media do
  @moduledoc """
  A recording of a book by a narrator.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Ambry.Books.Book
  alias Ambry.Media.Media
  alias Ambry.Media.Media.Chapter
  alias Ambry.Media.MediaNarrator
  alias Ambry.Media.PlayerState
  alias Ambry.Media.Processor
  alias Ambry.Repo.SupplementalFile
  alias Ambry.Thumbnails

  @statuses [:pending, :processing, :error, :ready]

  schema "media" do
    belongs_to :book, Book
    has_many :media_narrators, MediaNarrator, on_replace: :delete
    has_many :player_states, PlayerState
    has_many :authors, through: [:book, :authors]
    has_many :narrators, through: [:media_narrators, :narrator]

    embeds_many :chapters, Chapter, on_replace: :delete
    embeds_many :supplemental_files, SupplementalFile, on_replace: :delete
    embeds_one :thumbnails, Thumbnails, on_replace: :delete

    field :full_cast, :boolean, default: false
    field :status, Ecto.Enum, values: @statuses, default: :pending
    field :abridged, :boolean, default: false

    field :source_path, :string
    field :source_files, {:array, :string}, default: []
    field :mpd_path, :string
    field :hls_path, :string
    field :mp4_path, :string

    field :duration, :decimal

    field :published, :date
    field :published_format, Ecto.Enum, values: [:full, :year_month, :year]

    field :notes, :string

    field :image_path, :string
    field :description, :string
    field :publisher, :string

    timestamps(type: :utc_datetime)
  end

  def statuses, do: @statuses

  @doc false
  def changeset(media, attrs, for: :create) do
    media
    |> cast(attrs, [
      :abridged,
      :book_id,
      :full_cast,
      :source_path,
      :source_files,
      :published,
      :published_format,
      :notes,
      :image_path,
      :description,
      :publisher
    ])
    |> cast_assoc(:media_narrators,
      sort_param: :media_narrators_sort,
      drop_param: :media_narrators_drop
    )
    |> cast_embed(:supplemental_files)
    |> status_based_validation()
    |> validate_image_path()
  end

  def changeset(media, attrs, for: :update) do
    media
    |> cast(attrs, [
      :abridged,
      :book_id,
      :full_cast,
      :published,
      :published_format,
      :notes,
      :image_path,
      :description,
      :publisher
    ])
    |> cast_assoc(:media_narrators,
      sort_param: :media_narrators_sort,
      drop_param: :media_narrators_drop
    )
    |> cast_embed(:chapters,
      sort_param: :chapters_sort,
      drop_param: :chapters_drop
    )
    |> cast_embed(:supplemental_files,
      sort_param: :supplemental_files_sort,
      drop_param: :supplemental_files_drop
    )
    |> maybe_clear_thumbnails()
    |> status_based_validation()
    |> validate_image_path()
    |> check_constraint(:thumbnails, name: "thumbnails_original_match_constraint")
  end

  def changeset(media, attrs, for: :processor_update) do
    media
    |> cast(attrs, [
      :duration,
      :mp4_path,
      :mpd_path,
      :hls_path,
      :status
    ])
    |> status_based_validation()
  end

  def changeset(media, attrs, for: :thumbnails_update) do
    media
    |> cast(attrs, [])
    |> cast_embed(:thumbnails)
    |> check_constraint(:thumbnails, name: "thumbnails_original_match_constraint")
  end

  defp status_based_validation(changeset) do
    changeset
    # always required
    |> validate_required([
      :book_id,
      :full_cast,
      :status,
      :abridged,
      :source_path
    ])
    |> maybe_validate_paths()
  end

  defp maybe_validate_paths(changeset) do
    if get_field(changeset, :status) == :ready do
      validate_required(changeset, [
        :mpd_path,
        :hls_path,
        :mp4_path
      ])
    else
      changeset
    end
  end

  def source_id(%Media{source_path: nil}), do: Ecto.UUID.generate()
  def source_id(%Media{source_path: source_path}), do: Path.basename(source_path)

  def source_path(%Media{source_path: source_path}, file \\ "") when is_binary(source_path) do
    Path.join([source_path, file])
  end

  def output_id(media) do
    %{
      mp4_path: mp4_path,
      mpd_path: mpd_path,
      hls_path: hls_path
    } = media

    with [path | _] when is_binary(path) <- Enum.filter([mp4_path, mpd_path, hls_path], & &1),
         {:ok, id} <- path |> Path.basename() |> Path.rootname() |> Ecto.UUID.cast() do
      id
    else
      _anything ->
        Ecto.UUID.generate()
    end
  end

  def out_path(%Media{source_path: source_path}, file \\ "") when is_binary(source_path) do
    Path.join([source_path, "_out", file])
  end

  def files(%Media{source_files: [_ | _] = source_files}, extensions) do
    Processor.Shared.filter_filenames(source_files, extensions)
  end

  # DEPRECATED but still used by any older media that didn't set source_files
  def files(%Media{source_path: source_path}, extensions) when is_binary(source_path) do
    case File.ls(source_path) do
      {:ok, paths} ->
        paths
        |> Processor.Shared.filter_filenames(extensions)
        |> Enum.map(&Path.join(source_path, &1))

      {:error, _posix} ->
        []
    end
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
          if path |> Ambry.Paths.web_to_disk() |> File.exists?() do
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
