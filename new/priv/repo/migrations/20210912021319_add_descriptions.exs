defmodule Ambry.Repo.Migrations.AddDescriptions do
  use Ecto.Migration

  def change do
    alter table(:books) do
      add :description, :text
    end

    alter table(:authors) do
      add :description, :text
    end

    alter table(:narrators) do
      add :description, :text
    end
  end
end
