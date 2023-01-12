defmodule Ambry.Repo.Migrations.MediaPaths do
  use Ecto.Migration

  def change do
    rename table(:media), :path, to: :mpd_path

    alter table(:media) do
      add :source_path, :text
      add :mp4_path, :text

      modify :mpd_path, :text, null: true
    end
  end
end
