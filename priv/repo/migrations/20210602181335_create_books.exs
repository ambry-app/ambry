defmodule Ambry.Repo.Migrations.CreateBooks do
  use Ecto.Migration

  def change do
    create table(:books) do
      add :title, :text
      add :series_index, :decimal
      add :published, :date
      add :author_id, references(:authors, on_delete: :nothing)
      add :series_id, references(:series, on_delete: :nothing)

      timestamps()
    end

    create index(:books, [:author_id])
    create index(:books, [:series_id])
  end
end
