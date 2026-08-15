defmodule Ambry.Repo.Migrations.TagsAreClaimsNotFacts do
  @moduledoc """
  Records which of a file's own statements the operator has rejected.

  Everything else the import form reads is inspectable and overridable. The
  files' embedded tags were the exception: they fed matching invisibly, and
  a release tagged with its narrator in the author field, or with the series
  name where the author belongs, had no way to be told it was wrong. The
  escape hatch was to re-search by hand, which changed the *question* and
  left the answer still being graded against the junk.

  One row per rejected source, so an empty list means "believe the file",
  which is what every existing item means.
  """

  use Ecto.Migration

  def change do
    alter table(:inbox_items) do
      add :rejected_claims, {:array, :string}, null: false, default: []
    end
  end
end
