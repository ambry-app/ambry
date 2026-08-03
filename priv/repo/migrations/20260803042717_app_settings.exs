defmodule Ambry.Repo.Migrations.AppSettings do
  use Ecto.Migration

  # A tiny operator-editable key/value store, following the same rule the
  # metadata provider configs follow: a missing row means "the default", so
  # nothing has to be seeded and a fresh install behaves like a configured
  # one.
  #
  # Its first tenant is the direct-play publishing switch.
  def change do
    create table(:app_settings, primary_key: false) do
      timestamps(type: :utc_datetime)

      add :key, :string, primary_key: true
      add :value, :map, null: false, default: %{}
    end
  end
end
