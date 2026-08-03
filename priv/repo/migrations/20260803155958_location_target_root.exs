defmodule Ambry.Repo.Migrations.LocationTargetRoot do
  use Ecto.Migration

  # Which library root a downloads folder imports into.
  #
  # With one root this is obvious and stays null; the resolution falls back to
  # "the only root there is". With several it has to be said explicitly,
  # because the choice is not cosmetic: a hardlink can only be made within one
  # filesystem, so pairing a downloads folder with a root on the wrong NAS is
  # the difference between an import costing nothing and an import being
  # refused outright.
  #
  # Self-referential — a library root is just another location.
  def change do
    alter table(:library_locations) do
      add :target_root_id, references(:library_locations, on_delete: :nilify_all)
    end

    create index(:library_locations, [:target_root_id])
  end
end
