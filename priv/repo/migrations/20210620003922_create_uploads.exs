defmodule Ambry.Repo.Migrations.CreateUploads do
  use Ecto.Migration

  def change do
    create table(:uploads) do
      timestamps()

      add :temp_path, :text
    end
  end
end
