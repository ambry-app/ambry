defmodule Ambry.Repo.Migrations.Chapters do
  use Ecto.Migration

  def change do
    alter table(:media) do
      add :chapters, :jsonb
    end
  end
end
