defmodule Ambry.Repo.Migrations.MediaCustody do
  use Ecto.Migration

  # Custody says what Ambry is allowed to do to a recording's bytes — the
  # first mechanic of the storage model (roadmap 3a).
  #
  #   managed   files live in Ambry's own tree; it may organize, rename and
  #             delete them
  #   external  files are referenced where they lie, read-only; removing the
  #             recording deletes records only, never the files
  #
  # Existing media are `managed`: their sources were copied into
  # uploads/source_media at import, so they really are Ambry's to touch.
  # Approving from the inbox creates `external` recordings — files stay put.
  # Hardlinking messy sources into a library tree (managed) comes with the
  # rest of 3a.
  def change do
    alter table(:media) do
      add :custody, :text, null: false, default: "managed"
    end

    create constraint(:media, :media_custody_known, check: "custody in ('managed', 'external')")
  end
end
