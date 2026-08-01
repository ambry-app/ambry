defmodule Ambry.Repo.Migrations.RemoveTranslatorsAndLanguage do
  use Ecto.Migration
  use Familiar

  # Translator credits and the language field (added in the media version
  # fields migration) are deliberately removed before ever shipping in a
  # release: a third credit type taxes every future feature and the operator
  # doesn't want it. Only the display-title override remains.

  def up do
    update_view("media_flat", version: 9)

    drop table(:media_translators)

    execute "DELETE FROM deletions WHERE type = 'media_translator'"

    alter table(:media) do
      remove :language
    end
  end

  def down do
    alter table(:media) do
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
end
