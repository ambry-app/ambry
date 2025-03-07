defmodule Ambry.Repo.Migrations.AddThumbnailConstraints do
  use Ecto.Migration

  def change do
    execute """
            UPDATE people SET thumbnails = jsonb_set(people.thumbnails, '{original}', to_jsonb(people.image_path))
            WHERE people.thumbnails IS NOT NULL AND people.image_path IS NOT NULL;
            """,
            """
            UPDATE people SET thumbnails = people.thumbnails - 'original'
            WHERE people.thumbnails IS NOT NULL AND people.image_path IS NOT NULL;
            """

    create constraint(:people, :thumbnails_original_match_constraint,
             check:
               "thumbnails IS NULL OR (thumbnails->>'original' IS NOT NULL AND thumbnails->>'original' = image_path)"
           )
  end
end
