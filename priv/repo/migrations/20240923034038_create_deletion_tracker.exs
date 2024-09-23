defmodule Ambry.Repo.Migrations.CreateDeletionTracker do
  use Ecto.Migration

  def change do
    create table(:deletions) do
      add :type, :string, null: false
      add :record_id, :integer, null: false
      add :deleted_at, :utc_datetime, null: false
    end
  end
end
