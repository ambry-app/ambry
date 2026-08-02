defmodule Ambry.Repo.Migrations.MultiPartRecordings do
  use Ecto.Migration
  use Familiar

  def up do
    create table(:recording_groups) do
      add :name, :text

      timestamps(type: :utc_datetime)
    end

    alter table(:media) do
      add :part_number, :integer
      add :parts_total, :integer
      add :recording_group_id, references(:recording_groups, on_delete: :nilify_all)
    end

    create index(:media, [:recording_group_id])

    execute """
    CREATE TRIGGER track_delete_trigger
    BEFORE DELETE ON recording_groups
    FOR EACH ROW
    EXECUTE FUNCTION track_delete('recording_group');
    """

    update_view("media_flat", version: 10)
  end

  def down do
    update_view("media_flat", version: 9)

    alter table(:media) do
      remove :part_number
      remove :parts_total
      remove :recording_group_id
    end

    execute "DELETE FROM deletions WHERE type = 'recording_group'"

    drop table(:recording_groups)
  end
end
