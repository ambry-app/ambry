defmodule Ambry.Repo.Migrations.MoreUploadsFields do
  use Ecto.Migration

  def change do
    rename table(:uploads), :files, to: :source_files

    alter table(:uploads) do
      add :chapters, :jsonb
      add :supplemental_files, :jsonb
      add :status, :text, null: false, default: "pending"
      add :full_cast, :boolean, null: false
      add :abridged, :boolean, null: false
      add :published, :date
      add :published_format, :text, null: false, default: "full"
      add :notes, :text
      add :mpd_path, :text
      add :hls_path, :text
      add :mp4_path, :text
    end
  end
end
