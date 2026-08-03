defmodule Ambry.Repo.Migrations.MediaTracks do
  use Ecto.Migration

  # The direct-play data model (Phase 2a): a media is a list of ordered audio
  # files that clients play as-is, instead of a transcoded/packaged artifact.
  #
  # The table is multi-file-shaped even though direct-play v1 only ever writes
  # one track per media (multi-file books are deferred, see the roadmap's 2f):
  # ordered files with per-track duration and `start_offset` against one
  # continuous book timeline, so adding multi-track playback later is a
  # player-layer feature, not a data-model migration.
  #
  # Positions and progress events stay in absolute book-seconds throughout —
  # nothing about the sync model changes here.
  def change do
    create table(:media_tracks) do
      timestamps(type: :utc_datetime)

      add :media_id, references(:media, on_delete: :delete_all), null: false

      # position in the media's ordered track list, 0-based
      add :index, :integer, null: false

      # absolute path on disk; the file is played/served as-is, never rewritten
      add :path, :text, null: false
      add :size, :bigint, null: false

      # real container/codec facts as probed, never assumed — clients decide
      # playability from these (and a future compatibility fallback needs them
      # to be honest, see the roadmap's 2e)
      add :mime, :text
      add :format, :text
      add :codec, :text

      # seconds; `start_offset` is where this track begins on the book's
      # continuous timeline (always 0 while v1 writes a single track)
      add :duration, :numeric, null: false
      add :start_offset, :numeric, null: false, default: 0

      # whether seeking within this track lands where we say it does —
      # `approximate` covers e.g. VBR mp3 with no Xing/VBRI index
      add :seek_accuracy, :text, null: false, default: "exact"
    end

    create unique_index(:media_tracks, [:media_id, :index])

    create constraint(:media_tracks, :media_tracks_index_non_negative, check: "index >= 0")
    create constraint(:media_tracks, :media_tracks_size_non_negative, check: "size >= 0")
    create constraint(:media_tracks, :media_tracks_duration_positive, check: "duration > 0")

    create constraint(:media_tracks, :media_tracks_start_offset_non_negative,
             check: "start_offset >= 0"
           )
  end
end
