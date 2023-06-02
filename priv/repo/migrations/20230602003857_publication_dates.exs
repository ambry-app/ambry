defmodule Ambry.Repo.Migrations.PublicationDates do
  use Ecto.Migration
  use Familiar

  def change do
    drop_view("books_flat", revert: 3)

    alter table(:books) do
      add :published_format, :string, null: false, default: "full"
    end

    create_view("books_flat", version: 4)

    drop_view("media_flat", revert: 1)

    alter table(:media) do
      add :published, :date
      add :published_format, :string, null: false, default: "full"
    end

    create_view("media_flat", version: 2)
  end
end
