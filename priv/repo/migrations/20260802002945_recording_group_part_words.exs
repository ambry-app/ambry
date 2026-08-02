defmodule Ambry.Repo.Migrations.RecordingGroupPartWords do
  use Ecto.Migration
  use Familiar

  def up do
    alter table(:recording_groups) do
      add :part_word, :text
      add :part_word_plural, :text
    end

    update_view("media_flat", version: 11)
  end

  def down do
    update_view("media_flat", version: 10)

    alter table(:recording_groups) do
      remove :part_word
      remove :part_word_plural
    end
  end
end
