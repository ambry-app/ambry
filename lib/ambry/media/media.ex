defmodule Ambry.Media.Media do
  @moduledoc """
  A recording of a book by a narrator.
  """

  use Ecto.Schema

  import Ambry.Ecto.Positions
  import Ecto.Changeset

  alias Ambry.Books.Book
  alias Ambry.Hashids
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
  @custodies [:managed, :external]

  # Where this recording's chapter *markers* came from. One value for the
  # whole list, because markers arrive as a timeline from a single extractor
  # — you don't mix mp4 atoms with file boundaries. Titles are the opposite
  # and carry a source per row; see `Ambry.Media.Media.Chapter`.
  #
  # There is deliberately no `:provider` here. Provider chapter times
  # describe their own retail edition and drift by minutes against a rip, so
  # they are a title source only (roadmap 1h). `nil` means nobody recorded
  # it — every chapter list that predates this field.
  @marker_sources [:embedded, :file_boundaries, :manual]

  # provider-fillable scalar fields tracked by field-level provenance
  @provenance_fields [:published, :published_format, :publisher, :description, :image_path]

  schema "media" do
    belongs_to :book, Book
    belongs_to :recording_group, RecordingGroup
    has_many :media_narrators, MediaNarrator, on_replace: :delete, preload_order: [asc: :position]
    has_many :authors, through: [:book, :authors]
    has_many :narrators, through: [:media_narrators, :narrator]

    # direct-play: the ordered audio files clients play as-is. Empty for
    # legacy media, which stream/download the packaged artifacts below.
    has_many :media_tracks, MediaTrack, on_replace: :delete, preload_order: [asc: :index]

    embeds_many :chapters, Chapter, on_replace: :delete
    field :chapter_marker_source, Ecto.Enum, values: @marker_sources

    embeds_many :supplemental_files, SupplementalFile, on_replace: :delete
    embeds_one :thumbnails, Thumbnails, on_replace: :delete

    field :full_cast, :boolean, default: false
    field :status, Ecto.Enum, values: @statuses, default: :pending

    # When this recording's files stopped being readable. Deliberately not a
    # `status` value: status is about processing and is what publishing keys
    # on, while missing is orthogonal and — crucially — reversible. Set by
    # the reconciliation sweep and cleared when the files come back, so an
    # unplugged disk doesn't destroy what each recording's status used to be.
    field :missing_since, :utc_datetime

    # what Ambry may do to these bytes: `managed` files are its own to
    # organize and delete, `external` files are read where they lie and never
    # touched (roadmap 3a)
    field :custody, Ecto.Enum, values: @custodies, default: :managed
    field :abridged, :boolean, default: false

    # display-title override: how this recording's title differs from the
    # work's (translated/regional/retail title); nil means the book's title
    field :title, :string

    # multi-part recordings: this recording's position within its group —
    # meaningful only alongside recording_group_id (a part number without a
    # set is nonsense, enforced by CHECK); the set's total lives on the group
    field :part_number, :integer

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

  def custodies, do: @custodies

  def marker_sources, do: @marker_sources

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
      :recording_group_id,
      :source_path,
      :source_files,
      :custody,
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
      :status,
      :chapter_marker_source
    ])
    |> cast_assoc(:media_narrators,
      sort_param: :media_narrators_sort,
      drop_param: :media_narrators_drop
    )
    |> put_positions(:media_narrators)
    |> maybe_cast_tracks(attrs)
    |> cast_embed(:chapters,
      sort_param: :chapters_sort,
      drop_param: :chapters_drop
    )
    |> track_marker_source()
    |> cast_embed(:supplemental_files,
      sort_param: :supplemental_files_sort,
      drop_param: :supplemental_files_drop
    )
    |> validate_part_fields()
    |> maybe_clear_thumbnails()
    |> status_based_validation(opts)
    |> validate_image_path()
    |> cast_embed(:thumbnails)
    |> check_constraint(:thumbnails, name: "thumbnails_original_match_constraint")
    |> Provenance.track_changes(
      @provenance_fields ++ [:media_narrators],
      opts[:provenance] || %{}
    )
    |> track_chapters_provenance(opts[:provenance] || %{})
  end

  # Chapters join provenance only when a save carries a source for them (an
  # applied titles merge). They can't ride the tracked list above: an embed
  # with no primary key registers as changed on every cast, so blanket
  # tracking would stamp "manual, locked" onto the list every time the form
  # saves — and the rows already carry their own finer provenance in
  # `title_source`.
  defp track_chapters_provenance(changeset, sources) do
    case Map.get(sources, "chapters") do
      nil -> changeset
      source -> Provenance.track_changes(changeset, [:chapters], %{"chapters" => source})
    end
  end

  defp validate_part_fields(changeset) do
    changeset
    |> clear_part_when_detached()
    |> validate_number(:part_number, greater_than_or_equal_to: 1)
    |> validate_part_requires_group()
    |> validate_part_number_within_total()
    |> validate_group_book()
    |> check_constraint(:part_number, name: "media_part_number_requires_group")
  end

  # A group belongs to a book the way its members do — attaching a media to
  # another book's set is nonsense the tile renderer couldn't even display.
  # The total also becomes checkable here once the group is fetched.
  defp validate_group_book(changeset) do
    group_id = get_field(changeset, :recording_group_id)

    if group_id && (changed?(changeset, :recording_group_id) or changed?(changeset, :book_id)) do
      prepare_changes(changeset, &check_group_book(&1, group_id))
    else
      changeset
    end
  end

  defp check_group_book(changeset, group_id) do
    case changeset.repo.get(RecordingGroup, group_id) do
      %RecordingGroup{book_id: book_id} = group ->
        cond do
          book_id != get_field(changeset, :book_id) ->
            add_error(changeset, :recording_group_id, "belongs to a different book")

          over_total?(changeset, group) ->
            add_error(changeset, :part_number, "can't be greater than the total number of parts")

          true ->
            changeset
        end

      nil ->
        add_error(changeset, :recording_group_id, "does not exist")
    end
  end

  defp over_total?(changeset, %RecordingGroup{parts_total: total}) do
    part = get_field(changeset, :part_number)
    part && total && part > total
  end

  # Leaving the group takes the part number with it — a position in a set
  # the recording is no longer in isn't a fact to keep.
  defp clear_part_when_detached(changeset) do
    case fetch_change(changeset, :recording_group_id) do
      {:ok, nil} -> put_change(changeset, :part_number, nil)
      _unchanged_or_set -> changeset
    end
  end

  defp validate_part_requires_group(changeset) do
    if get_field(changeset, :part_number) && is_nil(get_field(changeset, :recording_group_id)) do
      add_error(changeset, :part_number, "requires a group")
    else
      changeset
    end
  end

  # The total lives on the group, so this check can only run where the total
  # is visible — the already-loaded linked group. Linking a different group
  # by id is covered only by the DB CHECKs; the group form validates its
  # members against the total itself.
  defp validate_part_number_within_total(changeset) do
    part_number = get_field(changeset, :part_number)
    parts_total = visible_parts_total(changeset)

    if part_number && parts_total && part_number > parts_total do
      add_error(changeset, :part_number, "can't be greater than the total number of parts")
    else
      changeset
    end
  end

  defp visible_parts_total(changeset) do
    case {changeset.data.recording_group, get_field(changeset, :recording_group_id)} do
      {%RecordingGroup{id: id, parts_total: total}, id} -> total
      _other -> nil
    end
  end

  @doc """
  The short identifier this recording's files carry in the library.

  A book folder is shared by every part of a set and by every recording of the
  same work, so two readings published the same year used to render to one
  identical path and placement refused. This is what makes a recording's name
  unique by construction instead — see `Ambry.Library.NamingTemplate.filenames/3`
  for why it's unconditional rather than only added on collision.

  It's the same `Ambry.Hashids` coder the track URLs use, on purpose: a token
  in a filename is then greppable back to the record it names, years later,
  by anyone holding the file.

  **That coder is `Hashids.new([])` — no salt, library defaults — so this is
  stable forever and identical in every environment. Giving it a salt or a
  `min_length` for some URL-side reason would silently rename every file in
  every library; `Ambry.HashidsTest` is the tripwire that stops it happening
  by accident.**
  """
  def filename_token(%Media{id: id}) when is_integer(id), do: Hashids.encode(id)
  def filename_token(%Media{}), do: nil

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

    case resolve_parts_total(media_ish, group) do
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

  # The total is the group's fact: an explicitly passed group, the loaded
  # group, or a flat row's parts_total column (sourced from the group in the
  # view). A Media with its group unloaded renders without the "of M".
  defp resolve_parts_total(_media_ish, %RecordingGroup{parts_total: total}), do: total

  defp resolve_parts_total(%Media{recording_group: %RecordingGroup{parts_total: total}}, nil),
    do: total

  defp resolve_parts_total(%{parts_total: total}, nil), do: total
  defp resolve_parts_total(_media_ish, nil), do: nil

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
  # Moving a marker makes the timeline the operator's, wherever it started
  # out. Titles are not markers, so pouring a provider's titles onto a
  # file-derived timeline leaves the source saying `:embedded` — which is the
  # whole point of tracking the two halves apart.
  #
  # Done here rather than at the call sites because every path that can edit
  # a time goes through this changeset, and four hand-rolled versions of one
  # invariant is how the last one got forgotten somewhere new.
  defp track_marker_source(changeset) do
    cond do
      get_change(changeset, :chapter_marker_source) -> changeset
      not marker_times_changed?(changeset) -> changeset
      true -> put_change(changeset, :chapter_marker_source, :manual)
    end
  end

  defp marker_times_changed?(changeset) do
    case fetch_change(changeset, :chapters) do
      {:ok, chapters} -> Chapter.times_moved?(changeset.data.chapters, chapters)
      :error -> false
    end
  end

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
