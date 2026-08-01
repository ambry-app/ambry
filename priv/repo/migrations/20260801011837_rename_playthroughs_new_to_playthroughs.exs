defmodule Ambry.Repo.Migrations.RenamePlaythroughsNewToPlaythroughs do
  use Ecto.Migration

  use Familiar

  # The previous migration dropped the legacy `playthroughs` table, freeing the
  # name for the event-sourced derived-state table to shed its transitional
  # `_new` suffix. Views referencing the table are rebuilt on the new name;
  # indexes and constraints are renamed to match.

  @indexes [
    "playthroughs_new_user_id_index",
    "playthroughs_new_media_id_index",
    "playthroughs_new_user_id_status_index",
    "playthroughs_new_last_event_at_index",
    "playthroughs_new_pkey"
  ]

  @constraints [
    "playthroughs_new_media_id_fkey",
    "playthroughs_new_user_id_fkey"
  ]

  def up do
    drop_view("users_flat")
    drop_view("playthroughs_flat")
    drop_view("devices_flat")

    rename table(:playthroughs_new), to: table(:playthroughs)

    for index <- @indexes do
      execute "ALTER INDEX #{index} RENAME TO #{rename_new(index)}"
    end

    for constraint <- @constraints do
      execute "ALTER TABLE playthroughs RENAME CONSTRAINT #{constraint} TO #{rename_new(constraint)}"
    end

    create_view("users_flat", version: 3)
    create_view("playthroughs_flat", version: 2)
    create_view("devices_flat", version: 3)
  end

  def down do
    drop_view("users_flat")
    drop_view("playthroughs_flat")
    drop_view("devices_flat")

    for constraint <- @constraints do
      execute "ALTER TABLE playthroughs RENAME CONSTRAINT #{rename_new(constraint)} TO #{constraint}"
    end

    for index <- @indexes do
      execute "ALTER INDEX #{rename_new(index)} RENAME TO #{index}"
    end

    rename table(:playthroughs), to: table(:playthroughs_new)

    create_view("users_flat", version: 2)
    create_view("playthroughs_flat", version: 1)
    create_view("devices_flat", version: 2)
  end

  defp rename_new(name), do: String.replace(name, "playthroughs_new", "playthroughs")
end
