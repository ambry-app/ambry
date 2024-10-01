defmodule Ambry.Repo.Migrations.AddThumbnails do
  use Ecto.Migration

  def change do
    alter table(:people) do
      add :thumbnails, :jsonb
    end

    alter table(:media) do
      add :thumbnails, :jsonb
    end
  end
end
