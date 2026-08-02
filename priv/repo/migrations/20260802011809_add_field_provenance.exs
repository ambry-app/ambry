defmodule Ambry.Repo.Migrations.AddFieldProvenance do
  use Ecto.Migration

  # Field-level metadata provenance (roadmap 1d): a jsonb map on each
  # provider-fillable table recording, per scalar field, where its current
  # value came from ("manual" | "legacy" | "provider:<id>") and whether it's
  # locked against automated overwrite.
  #
  # Backfill: every non-null tracked field on existing rows is marked
  # source=legacy and locked — years of hand-curation must never be clobbered
  # by future refresh/auto-match; the operator unlocks per field where
  # freshness is wanted. (published_format piggybacks on published: it always
  # has a default value, so it only gets an entry when a date is actually
  # set.)

  def up do
    alter table(:people) do
      add :field_provenance, :map, default: %{}, null: false
    end

    alter table(:books) do
      add :field_provenance, :map, default: %{}, null: false
    end

    alter table(:media) do
      add :field_provenance, :map, default: %{}, null: false
    end

    execute """
    UPDATE people SET field_provenance = jsonb_strip_nulls(jsonb_build_object(
      'name', CASE WHEN name IS NOT NULL THEN #{legacy_entry()} END,
      'description', CASE WHEN description IS NOT NULL THEN #{legacy_entry()} END,
      'image_path', CASE WHEN image_path IS NOT NULL THEN #{legacy_entry()} END
    ))
    """

    execute """
    UPDATE books SET field_provenance = jsonb_strip_nulls(jsonb_build_object(
      'title', CASE WHEN title IS NOT NULL THEN #{legacy_entry()} END,
      'published', CASE WHEN published IS NOT NULL THEN #{legacy_entry()} END,
      'published_format', CASE WHEN published IS NOT NULL THEN #{legacy_entry()} END
    ))
    """

    execute """
    UPDATE media SET field_provenance = jsonb_strip_nulls(jsonb_build_object(
      'published', CASE WHEN published IS NOT NULL THEN #{legacy_entry()} END,
      'published_format', CASE WHEN published IS NOT NULL THEN #{legacy_entry()} END,
      'publisher', CASE WHEN publisher IS NOT NULL THEN #{legacy_entry()} END,
      'description', CASE WHEN description IS NOT NULL THEN #{legacy_entry()} END,
      'image_path', CASE WHEN image_path IS NOT NULL THEN #{legacy_entry()} END
    ))
    """
  end

  def down do
    alter table(:people) do
      remove :field_provenance
    end

    alter table(:books) do
      remove :field_provenance
    end

    alter table(:media) do
      remove :field_provenance
    end
  end

  defp legacy_entry do
    """
    jsonb_build_object(
      'source', 'legacy',
      'locked', true,
      'at', to_char(now() AT TIME ZONE 'utc', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')
    )
    """
  end
end
