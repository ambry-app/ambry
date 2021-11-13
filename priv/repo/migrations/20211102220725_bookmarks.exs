defmodule Ambry.Repo.Migrations.Bookmarks do
  use Ecto.Migration

  def change do
    create table(:bookmarks) do
      timestamps()

      add :media_id, references(:media, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false

      add :position, :decimal, null: false
      add :label, :text
    end
  end
end
