defmodule Ambry.Media.MediaTrack do
  @moduledoc """
  One audio file belonging to a media, played directly by clients.

  Ordered by `index` and laid end-to-end on the book's continuous timeline,
  with `start_offset` in absolute book-seconds.

  `format`, `codec` and `mime` are recorded exactly as probed and never
  assumed playable, so a client can answer "can this device play this?" from
  synced track metadata alone.

  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Ambry.Hashids
  alias Ambry.Library
  alias Ambry.Library.Root
  alias Ambry.Media.Media
  alias Ambry.Media.MediaTrack

  @seek_accuracies [:exact, :approximate]

  schema "media_tracks" do
    belongs_to :media, Media

    # Which library root the file lives in; null means a legacy
    # `/uploads/...` path. Resolve through `disk_path/1`.
    belongs_to :library_root, Root

    field :index, :integer
    field :path, :string
    field :size, :integer
    field :mime, :string
    field :format, :string
    field :codec, :string
    field :duration, :decimal
    field :start_offset, :decimal, default: Decimal.new(0)
    field :seek_accuracy, Ecto.Enum, values: @seek_accuracies, default: :exact

    timestamps(type: :utc_datetime)
  end

  def seek_accuracies, do: @seek_accuracies

  @doc false
  def changeset(media_track, attrs) do
    media_track
    |> cast(attrs, [
      :index,
      :path,
      :library_root_id,
      :size,
      :mime,
      :format,
      :codec,
      :duration,
      :start_offset,
      :seek_accuracy
    ])
    |> validate_required([:index, :path, :size, :duration, :start_offset])
    |> validate_number(:index, greater_than_or_equal_to: 0)
    |> validate_number(:size, greater_than_or_equal_to: 0)
    |> validate_number(:duration, greater_than: 0)
    |> validate_number(:start_offset, greater_than_or_equal_to: 0)
    |> unique_constraint([:media_id, :index])
  end

  @doc """
  The URL clients fetch this track from.

  Keyed on the track rather than its path, which is root-relative, and ending
  in the file's real name so downloads keep their extension.
  """
  def web_path(%MediaTrack{id: id, path: path}) do
    "/files/track/#{Hashids.encode(id)}/#{Path.basename(path)}"
  end

  @doc """
  The absolute disk path this track is served from.
  """
  def disk_path(%MediaTrack{path: "/uploads/" <> _rest = web_path}),
    do: Library.resolve(nil, web_path)

  def disk_path(%MediaTrack{library_root: %Root{} = root, path: path}),
    do: Library.resolve(root, path)

  def disk_path(%MediaTrack{library_root_id: root_id, path: path}),
    do: Library.resolve(root_id, path)

  @doc """
  The same, for callers with nothing sensible to do about an unresolvable
  path: it is a broken invariant rather than a missing file, and belongs in
  the log as one.
  """
  def disk_path!(%MediaTrack{} = track) do
    {:ok, path} = disk_path(track)
    path
  end

  @doc """
  The absolute book-seconds range this track covers, as `{start, end}`.
  """
  def range(%MediaTrack{start_offset: start_offset, duration: duration}) do
    {start_offset, Decimal.add(start_offset, duration)}
  end
end
