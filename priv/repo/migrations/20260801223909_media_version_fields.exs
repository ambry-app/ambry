defmodule Ambry.Repo.Migrations.MediaVersionFields do
  use Ecto.Migration
  use Familiar

  def up do
    alter table(:media) do
      add :title, :text
      add :language, :text
    end

    create table(:media_translators) do
      add :media_id, references(:media, on_delete: :delete_all), null: false
      add :author_id, references(:authors), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:media_translators, [:media_id, :author_id])
    create index(:media_translators, [:author_id])

    execute """
    CREATE TRIGGER track_delete_trigger
    BEFORE DELETE ON media_translators
    FOR EACH ROW
    EXECUTE FUNCTION track_delete('media_translator');
    """

    update_view("media_flat", version: 8)
  end

  def down do
    update_view("media_flat", version: 7)

    drop table(:media_translators)

    alter table(:media) do
      remove :title
      remove :language
    end
  end
end
