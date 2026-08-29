defmodule Ambry.Repo.Migrations.AddUnlistedAtToMedia do
  use Ecto.Migration

  def change do
    alter table(:media) do
      add :unlisted_at, :utc_datetime
    end
  end
end
