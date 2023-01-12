defmodule Ambry.Repo.Migrations.FullCast do
  use Ecto.Migration

  def change do
    alter table(:media) do
      add :full_cast, :boolean, default: false
    end
  end
end
