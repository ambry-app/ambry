defmodule Ambry.Repo.Migrations.AddHlsPathToMedia do
  use Ecto.Migration

  def change do
    alter table(:media) do
      add :hls_path, :text
    end
  end
end
