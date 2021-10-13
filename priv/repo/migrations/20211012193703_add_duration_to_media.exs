defmodule Ambry.Repo.Migrations.AddDurationToMedia do
  use Ecto.Migration

  def change do
    alter table(:media) do
      add :duration, :decimal
    end
  end
end
