defmodule Ambry.Repo.Migrations.MediaInsteadOfUploads do
  use Ecto.Migration

  def change do
    alter table(:media) do
      add :status, :text, null: false, default: "pending"
    end

    drop table(:uploads)
  end
end
