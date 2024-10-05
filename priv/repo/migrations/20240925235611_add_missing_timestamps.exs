defmodule Ambry.Repo.Migrations.AddMissingTimestamps do
  use Ecto.Migration

  def change do
    alter table(:authors_books) do
      timestamps(type: :utc_datetime, default: fragment("NOW()"))
    end

    alter table(:books_series) do
      timestamps(type: :utc_datetime, default: fragment("NOW()"))
    end

    alter table(:media_narrators) do
      timestamps(type: :utc_datetime, default: fragment("NOW()"))
    end
  end
end
