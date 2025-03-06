defmodule Ambry.Repo.Migrations.AddMediaThumbnailConstraints do
  use Ecto.Migration

  def change do
    execute """
            UPDATE media SET thumbnails = jsonb_set(media.thumbnails, '{original}', to_jsonb(media.image_path))
            WHERE media.thumbnails IS NOT NULL AND media.image_path IS NOT NULL;
            """,
            """
            UPDATE media SET thumbnails = media.thumbnails - 'original'
            WHERE media.thumbnails IS NOT NULL AND media.image_path IS NOT NULL;
            """

    create constraint(:media, :thumbnails_original_match_constraint,
             check:
               "thumbnails IS NULL OR (thumbnails->>'original' IS NOT NULL AND thumbnails->>'original' = image_path)"
           )
  end
end
