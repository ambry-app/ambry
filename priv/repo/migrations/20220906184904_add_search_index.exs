defmodule Ambry.Repo.Migrations.AddSearchIndex do
  use Ecto.Migration
  use Familiar

  def up do
    execute """
    CREATE TYPE reference AS (type text, id bigint);
    """

    create table(:search_index, primary_key: false) do
      add :reference, :reference, null: false, primary_key: true
      add :dependencies, {:array, :reference}, null: false, default: []
      add :primary, :text
      add :secondary, :text
      add :tertiary, :text
      add :search_vector, :tsvector, null: false
    end

    create index(:search_index, [:dependencies])
    create index(:search_index, [:search_vector], name: :search_vector_idx, using: "GIN")

    create_function("update_index_search_vector", version: 1)

    execute """
    CREATE TRIGGER update_tsvector
    BEFORE INSERT OR UPDATE ON search_index
    FOR EACH ROW
    EXECUTE FUNCTION update_index_search_vector();
    """
  end

  def down do
    execute """
    DROP TRIGGER update_tsvector ON search_index;
    """

    drop_function("update_index_search_vector", version: 1)

    drop table(:search_index)

    execute """
    DROP TYPE reference;
    """
  end
end
