defmodule Ambry.Repo.Migrations.UploadNarrators do
  use Ecto.Migration

  def change do
    create table(:upload_narrators) do
      add :upload_id, references(:uploads), null: false
      add :narrator_id, references(:narrators), null: false
    end
  end
end
