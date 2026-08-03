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
  alias Ambry.Media.MediaTrack
  alias Ambry.Media.Processor
  alias Ambry.Media.RecordingGroup
  alias Ambry.Provenance
  alias Ambry.Repo.SupplementalFile
  alias Ambry.Thumbnails

  @statuses [:pending, :processing, :error, :ready]

  # provider-fillable scalar fields tracked by field-level provenance
  @provenance_fields [:published, :published_format, :publisher, :description, :image_path]

  schema "media" do
    belongs_to :book, Book
    belongs_to :recording_group, RecordingGroup
    has_many :media_narrators, MediaNarrator, on_replace: :delete
    has_many :authors, through: [:book, :authors]
    has_many :narrators, through: [:media_narrators, :narrator]

    # direct-play: the ordered audio files clients play as-is. Empty for
    # legacy media, which stream/download the packaged artifacts below.
    has_many :media_tracks, MediaTrack, on_replace: :delete, preload_order: [asc: :index]

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
    field :recording_group_name, :string, virtual: true
    field :recording_group_show_label, :boolean, virtual: true
    field :recording_group_part_word, :string, virtual: true
    field :recording_group_part_word_plural, :string, virtual: true

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

    field :field_provenance, :map, default: %{}

    timestamps(type: :utc_datetime)
  end

  def statuses, do: @statuses

  def provenance_fields, do: @provenance_fields

  @doc false
  def changeset(media, attrs, opts \\ []) do
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
      :recording_group_show_label,
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
    |> maybe_cast_tracks(attrs)
    |> cast_embed(:chapters,
      sort_param: :chapters_sort,
      drop_param: :chapters_drop
    )
    |> cast_embed(:supplemental_files,
      sort_param: :supplemental_files_sort,
      drop_param: :supplemental_files_drop
    )
    |> cast(
      attrs,
      [:recording_group_name, :recording_group_part_word, :recording_group_part_word_plural],
      empty_values: []
    )
    |> apply_recording_group_choice()
    |> maybe_rename_recording_group()
    |> validate_part_fields()
    |> maybe_clear_thumbnails()
    |> status_based_validation(opts)
    |> validate_image_path()
    |> cast_embed(:thumbnails)
    |> check_constraint(:thumbnails, name: "thumbnails_original_match_constraint")
    |> Provenance.track_changes(@provenance_fields, opts[:provenance] || %{})
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
        put_assoc(changeset, :recording_group, %RecordingGroup{
          name: presence(get_change(changeset, :recording_group_name)),
          show_label: get_change(changeset, :recording_group_show_label) == true,
          part_word: group_word_change(changeset, :recording_group_part_word),
          part_word_plural: group_word_change(changeset, :recording_group_part_word_plural)
        })

      id ->
        case Integer.parse(id) do
          {id, ""} -> put_change(changeset, :recording_group_id, id)
          _else -> add_error(changeset, :recording_group_choice, "is invalid")
        end
    end
  end

  # Updates the currently-linked group's label/wording (shared by all its
  # parts) when the form's fields changed. Only applies while the media stays
  # linked to that same group — picking a different or new group ignores it.
  defp maybe_rename_recording_group(changeset) do
    group = changeset.data.recording_group

    updates =
      [
        name: get_change(changeset, :recording_group_name),
        show_label: get_change(changeset, :recording_group_show_label),
        part_word: get_change(changeset, :recording_group_part_word),
        part_word_plural: get_change(changeset, :recording_group_part_word_plural)
      ]
      |> Enum.reject(fn {_field, value} -> is_nil(value) end)
      |> Map.new(fn {field, value} -> {field, group_update_value(field, value)} end)

    with false <- updates == %{},
         false <- get_change(changeset, :recording_group_choice) == "new",
         %RecordingGroup{} <- group,
         true <- get_field(changeset, :recording_group_id) == group.id,
         true <- Enum.any?(updates, fn {field, value} -> Map.get(group, field) != value end) do
      put_assoc(changeset, :recording_group, RecordingGroup.changeset(group, updates))
    else
      _no_update -> changeset
    end
  end

  # the label-visibility flag is a boolean — everything else is a string
  # that folds empty to nil
  defp group_update_value(:show_label, value), do: value
  defp group_update_value(_field, value), do: presence(value)

  defp group_word_change(changeset, field) do
    changeset |> get_change(field) |> presence_downcase()
  end

  defp presence_downcase(nil), do: nil
  defp presence_downcase(string), do: string |> presence() |> then(&(&1 && String.downcase(&1)))

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
  A human label for a media's position in its part set ("Part 2 of 3",
  "Episode 4" per the group's wording), or nil for single-release
  recordings. Works on anything with the part fields (Media structs and
  MediaFlat rows alike); the wording comes from the loaded recording group,
  a flat row's part_word column, or an explicitly passed group.
  """
  def part_label(media_ish, group \\ nil)
  def part_label(%{part_number: nil}, _group), do: nil

  def part_label(%{part_number: n} = media_ish, group) do
    word = media_ish |> resolve_part_word(group) |> String.capitalize()

    case media_ish.parts_total do
      nil -> "#{word} #{n}"
      total -> "#{word} #{n} of #{total}"
    end
  end

  defp resolve_part_word(_media_ish, %RecordingGroup{} = group),
    do: RecordingGroup.part_word(group)

  defp resolve_part_word(%Media{recording_group: %RecordingGroup{} = group}, nil),
    do: RecordingGroup.part_word(group)

  defp resolve_part_word(%{part_word: word}, nil) when is_binary(word), do: word
  defp resolve_part_word(_media_ish, nil), do: "part"

  defp status_based_validation(changeset, opts) do
    changeset
    # always required
    |> validate_required([
      :book_id,
      :full_cast,
      :status,
      :abridged,
      :source_path
    ])
    |> maybe_validate_paths(opts)
  end

  # A ready media needs *some* playable representation. Direct-play media have
  # tracks; legacy media have the packaged artifacts, which is why the trio is
  # nullable rather than gone — already-imported media keep playing untouched
  # until the back-catalog reclaim retires them.
  #
  # Publishing a tracks-only recording is additionally gated on the operator
  # switch, because the app has to understand tracks before the server ever
  # hands it one. Callers pass `direct_play_publishing?` in; the context reads
  # the setting so this stays a pure function of its inputs.
  defp maybe_validate_paths(changeset, opts) do
    cond do
      get_field(changeset, :status) != :ready ->
        changeset

      not direct_play?(changeset) ->
        validate_required(changeset, [
          :mpd_path,
          :hls_path,
          :mp4_path
        ])

      # The gate applies to the act of publishing, not to every later edit:
      # turning the switch back off must not strand recordings that are
      # already live, or leave them uneditable.
      get_change(changeset, :status) == :ready and !opts[:direct_play_publishing?] ->
        add_error(
          changeset,
          :status,
          "can't be ready: direct-play publishing is switched off"
        )

      true ->
        changeset
    end
  end

  # An unloaded assoc can't vouch for itself, so it reads as "no tracks" and
  # the legacy paths stay required. `get_media!/1` preloads tracks, so every
  # caller that edits an existing media sees the truth.
  defp direct_play?(changeset) do
    case tracks(changeset) do
      [_ | _] -> true
      _no_tracks -> false
    end
  end

  defp tracks(changeset) do
    case changeset.changes do
      %{media_tracks: tracks} -> tracks
      _unchanged -> loaded_tracks(changeset.data)
    end
  end

  defp loaded_tracks(%Media{media_tracks: %Ecto.Association.NotLoaded{}}), do: []
  defp loaded_tracks(%Media{media_tracks: tracks}), do: tracks
  defp loaded_tracks(_data), do: []

  # Tracks are written by the scanner, never by a form: the admin forms don't
  # submit the param, and casting an assoc they never loaded would raise.
  defp maybe_cast_tracks(changeset, attrs) do
    if Map.has_key?(attrs, :media_tracks) or Map.has_key?(attrs, "media_tracks") do
      cast_assoc(changeset, :media_tracks)
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
