defmodule Ambry.Repo.Migrations.AddSourceFilesToMedia do
  use Ecto.Migration

  def change do
    alter table(:media) do
      add :source_files, {:array, :text}, default: [], null: false
    end
  end
end
