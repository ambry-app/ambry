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
  alias Ambry.Media.Processor
  alias Ambry.Media.RecordingGroup
  alias Ambry.Repo.SupplementalFile
  alias Ambry.Thumbnails

  @statuses [:pending, :processing, :error, :ready]

  schema "media" do
    belongs_to :book, Book
    belongs_to :recording_group, RecordingGroup
    has_many :media_narrators, MediaNarrator, on_replace: :delete
    has_many :authors, through: [:book, :authors]
    has_many :narrators, through: [:media_narrators, :narrator]

    embeds_many :chapters, Chapter, on_replace: :delete
    embeds_many :supplemental_files, SupplementalFile, on_replace: :delete
    embeds_one :thumbnails, Thumbnails, on_replace: :delete

    field :full_cast, :boolean, default: false
    field :status, Ecto.Enum, values: @statuses, default: :pending
    field :abridged, :boolean, default: false

    # display-title override: how this recording's title differs from the
    # work's (translated/regional/retail title); nil means the book's title
    field :title, :string

    # multi-part recordings: each part is a full media of the same book,
    # optionally labeled "Part N of M" and grouped with its siblings
    field :part_number, :integer
    field :parts_total, :integer

    # form-only: recording-group picker staging, see apply_recording_group_choice/1
    field :recording_group_choice, :string, virtual: true
    field :new_recording_group_name, :string, virtual: true

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
  def changeset(media, attrs) do
    media
    |> cast(attrs, [
      :abridged,
      :book_id,
      :full_cast,
      :title,
      :part_number,
      :parts_total,
      :recording_group_id,
      :recording_group_choice,
      :new_recording_group_name,
      :source_path,
      :source_files,
      :published,
      :published_format,
      :notes,
      :image_path,
      :description,
      :publisher,
      :duration,
      :mp4_path,
      :mpd_path,
      :hls_path,
      :status
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
    |> apply_recording_group_choice()
    |> validate_part_fields()
    |> maybe_clear_thumbnails()
    |> status_based_validation()
    |> validate_image_path()
    |> cast_embed(:thumbnails)
    |> check_constraint(:thumbnails, name: "thumbnails_original_match_constraint")
  end

  # The media form stages the recording-group picker in a virtual field:
  # "none" clears the group, "new" creates one (with the optional name from
  # new_recording_group_name) atomically at save, and an id links it. ("" is
  # unusable as the clear sentinel — Ecto casts it to nil, i.e. "untouched".)
  # Callers that set recording_group_id directly bypass this entirely.
  defp apply_recording_group_choice(changeset) do
    case get_change(changeset, :recording_group_choice) do
      nil ->
        changeset

      "none" ->
        put_change(changeset, :recording_group_id, nil)

      "new" ->
        name = presence(get_change(changeset, :new_recording_group_name))
        put_assoc(changeset, :recording_group, %RecordingGroup{name: name})

      id ->
        case Integer.parse(id) do
          {id, ""} -> put_change(changeset, :recording_group_id, id)
          _else -> add_error(changeset, :recording_group_choice, "is invalid")
        end
    end
  end

  defp presence(nil), do: nil
  defp presence(string) when is_binary(string), do: with("" <- String.trim(string), do: nil)

  defp validate_part_fields(changeset) do
    changeset
    |> validate_number(:part_number, greater_than_or_equal_to: 1)
    |> validate_number(:parts_total, greater_than_or_equal_to: 1)
    |> validate_part_number_within_total()
  end

  defp validate_part_number_within_total(changeset) do
    part_number = get_field(changeset, :part_number)
    parts_total = get_field(changeset, :parts_total)

    if part_number && parts_total && part_number > parts_total do
      add_error(changeset, :part_number, "can't be greater than the total number of parts")
    else
      changeset
    end
  end

  @doc """
  The title this recording displays as: the override verbatim when set
  (retail overrides already carry their own part designation), otherwise the
  book's title plus the part label. Requires `book` to be preloaded.
  """
  def display_title(%Media{title: title}) when is_binary(title), do: title

  def display_title(%Media{} = media) do
    case part_label(media) do
      nil -> media.book.title
      label -> "#{media.book.title} (#{label})"
    end
  end

  @doc """
  A human label for a media's position in its part set, or nil for
  single-release recordings. Works on anything with the part fields
  (Media structs and MediaFlat rows alike).
  """
  def part_label(%{part_number: nil}), do: nil
  def part_label(%{part_number: n, parts_total: nil}), do: "Part #{n}"
  def part_label(%{part_number: n, parts_total: total}), do: "Part #{n} of #{total}"

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
