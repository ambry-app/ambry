defmodule Ambry.Repo.Migrations.MediaNotes do
  use Ecto.Migration

  def change do
    alter table(:media) do
      add :notes, :text
    end
  end
end
