defmodule Ambry.Repo.Migrations.AllowNullHashedPassword do
  use Ecto.Migration

  def up do
    alter table(:users) do
      modify :hashed_password, :string, null: true
    end
  end

  def down do
    alter table(:users) do
      modify :hashed_password, :string, null: false
    end
  end
end
