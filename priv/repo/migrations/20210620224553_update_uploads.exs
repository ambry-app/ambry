defmodule Ambry.Repo.Migrations.UpdateUploads do
  use Ecto.Migration

  def change do
    alter table(:uploads) do
      add :full_cast, :boolean, null: false
      add :narrators, {:array, :integer}, null: false
      add :status, :text, null: false
    end
  end
end
