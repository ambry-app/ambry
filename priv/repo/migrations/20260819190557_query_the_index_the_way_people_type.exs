defmodule Ambry.Repo.Migrations.QueryTheIndexTheWayPeopleType do
  @moduledoc """
  Two query-side corrections, both found by searching the real library.

  A stop word carried alongside real terms is not a search term — under
  `:any` it OR'd in most of the library, and `ts_rank_cd` counted it as
  evidence, so "the end of all things" reached 239 of 419 books and ranked
  Order of the Phoenix third. It stays a search term only when the phrase is
  nothing but stop words, which is the case it was added for.

  And the prefix belongs to what was typed, not to its stem: v2 stemmed and
  then appended `:*`, so "mars" became `'mar':*` and matched Martha, Marlon,
  Markson, Marin, Martin, Marsters, Marissa and Maryam.

  Query-side only. `ambry_tsquery` appears in no index expression and in no
  stored vector, so nothing needs rebuilding and this is safe to run against
  an instance already serving traffic.
  """

  use Ecto.Migration
  use Familiar

  def up do
    replace_function("ambry_tsquery", version: 3, revert: 2)
  end

  def down do
    replace_function("ambry_tsquery", version: 2)
  end
end
