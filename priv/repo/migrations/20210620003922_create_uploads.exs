defmodule Ambry.Repo.Migrations.CreateUploads do
  use Ecto.Migration

  def change do
    create table(:uploads) do
      add :temp_path, :text

      timestamps()
    end
  end
end
