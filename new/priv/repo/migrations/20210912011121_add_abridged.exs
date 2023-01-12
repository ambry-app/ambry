defmodule Ambry.Repo.Migrations.AddAbridged do
  use Ecto.Migration

  def change do
    alter table(:media) do
      add :abridged, :boolean, null: false
    end
  end
end
