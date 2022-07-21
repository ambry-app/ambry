defmodule Ambry.Repo.Migrations.AddShelves do
  use Ecto.Migration

  def change do
    create table(:shelves) do
      timestamps()

      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :order, :integer, null: false
    end

    create index(:shelves, [:user_id])

    create table(:media_shelves) do
      timestamps()

      add :media_id, references(:media, on_delete: :delete_all), null: false
      add :shelf_id, references(:shelves, on_delete: :delete_all), null: false
      add :order, :integer, null: false
    end

    create index(:media_shelves, [:media_id])
    create index(:media_shelves, [:shelf_id])
  end
end
