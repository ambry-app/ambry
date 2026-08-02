defmodule Ambry.Repo.Migrations.AddRecordingGroupShowLabel do
  use Ecto.Migration

  # Reversed decision (v1.9.0 punch list): whether a group's label renders
  # on its stacked tile is an explicit per-group operator choice — a
  # dedicated flag, never inferred from label presence.
  def change do
    alter table(:recording_groups) do
      add :show_label, :boolean, default: false, null: false
    end
  end
end
