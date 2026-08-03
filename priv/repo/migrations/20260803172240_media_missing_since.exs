defmodule Ambry.Repo.Migrations.MediaMissingSince do
  use Ecto.Migration

  # When a recording's files stopped being there (roadmap 3b reconciliation).
  #
  # Deliberately NOT a new `status` value, though the roadmap phrases it as
  # "mark media missing". Status is a state machine about processing —
  # pending → processing → ready/error — and it is what publishing keys on.
  # Missing is orthogonal to all of that: a ready recording whose NAS is
  # unplugged is still *meant* to be ready, it just can't be played this
  # minute.
  #
  # The deciding argument is reversibility. Overwriting `status` destroys
  # what the recording was before, so remounting a disk that held 300
  # recordings would leave no way to know which were ready and which were
  # still pending. A separate timestamp is set when the files vanish and
  # cleared when they come back, and nothing else has to be remembered.
  #
  # Nothing cascades from this. It is a note that something is wrong, not a
  # deletion — the files may simply be on a disk that is currently unplugged.
  def change do
    alter table(:media) do
      add :missing_since, :utc_datetime
    end

    create index(:media, [:missing_since])
  end
end
