defmodule Ambry.Repo.Migrations.AddImages do
  use Ecto.Migration

  def change do
    alter table(:authors) do
      add :image_path, :text
    end

    alter table(:books) do
      add :image_path, :text
    end

    alter table(:narrators) do
      add :image_path, :text
    end
  end
end
