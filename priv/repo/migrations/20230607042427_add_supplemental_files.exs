defmodule Ambry.Repo.Migrations.AddSupplementalFiles do
  use Ecto.Migration

  def change do
    alter table(:media) do
      add :supplemental_files, :jsonb
    end
  end
end
