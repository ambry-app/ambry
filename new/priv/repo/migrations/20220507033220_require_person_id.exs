defmodule Ambry.Repo.Migrations.RequirePersonId do
  use Ecto.Migration
  use Familiar

  def up do
    wrapper(fn ->
      alter table(:authors) do
        modify :person_id, references(:people, on_delete: :delete_all), null: false
      end

      alter table(:narrators) do
        modify :person_id, references(:people, on_delete: :delete_all), null: false
      end
    end)
  end

  def down do
    wrapper(fn ->
      alter table(:authors) do
        modify :person_id, references(:people)
      end

      alter table(:narrators) do
        modify :person_id, references(:people)
      end
    end)
  end

  defp wrapper(fun) do
    drop_view("people_flat")
    drop_view("series_flat")
    drop_view("media_flat")
    drop_view("books_flat")

    drop constraint(:authors, "authors_person_id_fkey")
    drop constraint(:narrators, "narrators_person_id_fkey")

    fun.()

    create_view("people_flat", version: 1)
    create_view("series_flat", version: 1)
    create_view("media_flat", version: 1)
    create_view("books_flat", version: 3)
  end
end
