defmodule Ambry.Media.Media do
  @moduledoc """
  A recording of a book by a narrator.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Ambry.Books.Book
  alias Ambry.Media.{Media, MediaNarrator, PlayerState, Processor}
  alias Ambry.Media.Media.Chapter
  alias Ambry.Narrators.Narrator

  @statuses [:pending, :processing, :error, :ready]

  schema "media" do
    belongs_to :book, Book
    has_many :media_narrators, MediaNarrator
    has_many :player_states, PlayerState
    has_many :authors, through: [:book, :authors]
    many_to_many :narrators, Narrator, join_through: "media_narrators"

    embeds_many :chapters, Chapter, on_replace: :delete

    field :full_cast, :boolean, default: false
    field :status, Ecto.Enum, values: @statuses, default: :pending
    field :abridged, :boolean, default: false

    field :source_path, :string
    field :mpd_path, :string
    field :hls_path, :string
    field :mp4_path, :string

    field :duration, :decimal

    field :published, :date
    field :published_format, Ecto.Enum, values: [:full, :year_month, :year]

    timestamps()
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
      :published,
      :published_format
    ])
    |> cast_assoc(:media_narrators)
    |> status_based_validation()
  end

  def changeset(media, attrs, for: :update) do
    media
    |> cast(attrs, [
      :abridged,
      :book_id,
      :full_cast,
      :published,
      :published_format
    ])
    |> cast_assoc(:media_narrators)
    |> cast_embed(:chapters)
    |> status_based_validation()
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

  def files(%Media{source_path: source_path}, extensions, opts \\ [])
      when is_binary(source_path) do
    full? = Keyword.get(opts, :full?, false)

    case File.ls(source_path) do
      {:ok, paths} ->
        paths = Processor.Shared.filter_filenames(paths, extensions)

        if full? do
          Enum.map(paths, &Path.join(source_path, &1))
        else
          paths
        end

      {:error, _posix} ->
        []
    end
  end
end
