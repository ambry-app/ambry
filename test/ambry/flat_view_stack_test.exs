defmodule Ambry.FlatViewStackTest do
  @moduledoc """
  The admin list cover-stacks (books/series/universes flat views) follow
  the tile-system-v2 Edition rules — one cover per edition (books view),
  one cover per book via its newest edition's representative (series and
  universes views) — while deliberately including non-ready media (admin
  lists are ops views). The SQL is a twin of `Ambry.Media.Editions`; the
  parity tests here are what hold the two in lockstep.
  """
  use Ambry.DataCase

  alias Ambry.Books.BookFlat
  alias Ambry.Books.SeriesFlat
  alias Ambry.Books.UniverseFlat
  alias Ambry.Media.Editions
  alias Ambry.Repo

  # the thumbnails constraint only requires original == image_path, so fake
  # covers are enough to drive the views' ARRAY subqueries
  defp insert_media_with_cover(book, tag, attrs) do
    path = "/uploads/images/#{tag}.webp"

    thumbnails = %Ambry.Thumbnails{
      original: path,
      extra_small: "#{path}-xs",
      small: "#{path}-sm",
      medium: "#{path}-md",
      large: "#{path}-lg",
      extra_large: "#{path}-xl"
    }

    insert(:media, [book: book, image_path: path, thumbnails: thumbnails] ++ attrs)
  end

  defp small_thumb(media), do: media.thumbnails.small

  defp elixir_edition_thumbs(media_list) do
    media_list
    |> Editions.from_media(all_statuses: true)
    |> Enum.map(& &1.representative.thumbnails)
    |> Enum.filter(& &1)
    |> Enum.map(& &1.small)
  end

  test "books view: one cover per edition, newest first, groups collapse to first part" do
    book = insert(:book)
    group = insert(:recording_group, parts_total: 3)

    solo = insert_media_with_cover(book, "solo", status: :ready, published: ~D[2020-01-01])

    pending =
      insert_media_with_cover(book, "pending", status: :pending, published: ~D[2022-01-01])

    parts =
      for n <- 1..3 do
        insert_media_with_cover(book, "part#{n}",
          part_number: n,
          recording_group: group,
          status: :ready,
          published: ~D[2021-01-01]
        )
      end

    [part_one | _rest] = parts

    flat = Repo.get!(BookFlat, book.id)

    # newest edition first; non-ready included (ops view); the group is one
    # cover — its first part
    assert flat.thumbnails == [small_thumb(pending), small_thumb(part_one), small_thumb(solo)]

    # parity with the Elixir Editions rules (the lockstep contract)
    assert flat.thumbnails == elixir_edition_thumbs([solo, pending | parts])
  end

  test "books view: the sole-edition exception is gone — a lone group is ONE cover" do
    book = insert(:book)
    group = insert(:recording_group, parts_total: 3)

    [part_one | _rest] =
      for n <- 1..3 do
        insert_media_with_cover(book, "part#{n}",
          part_number: n,
          recording_group: group,
          status: :ready
        )
      end

    flat = Repo.get!(BookFlat, book.id)

    assert flat.thumbnails == [small_thumb(part_one)]
  end

  test "series and universe views: one cover per book (newest edition's representative), in order" do
    series = insert(:series)
    universe = insert(:universe)

    book_two =
      insert(:book,
        title: "B Book",
        series_books: [%{series: series, book_number: 2}],
        book_universes: [%{universe: universe}]
      )

    book_one =
      insert(:book,
        title: "A Book",
        series_books: [%{series: series, book_number: 1}],
        book_universes: [%{universe: universe}]
      )

    # book one: an old solo and a newer group — its cover is the group's
    # first part (the newest edition's representative)
    group = insert(:recording_group, parts_total: 2)
    insert_media_with_cover(book_one, "solo", status: :ready, published: ~D[2019-01-01])

    [g_part_one | _rest] =
      for n <- 1..2 do
        insert_media_with_cover(book_one, "part#{n}",
          part_number: n,
          recording_group: group,
          status: :ready,
          published: ~D[2021-01-01]
        )
      end

    # book two: a single pending edition — still visible on admin lists
    b2_media = insert_media_with_cover(book_two, "b2", status: :pending)

    # a book with no media contributes nothing
    insert(:book,
      title: "C Book",
      series_books: [%{series: series, book_number: 3}],
      book_universes: [%{universe: universe}]
    )

    expected = [small_thumb(g_part_one), small_thumb(b2_media)]

    # series order (book number) and universe order (title) agree here
    assert Repo.get!(SeriesFlat, series.id).thumbnails == expected
    assert Repo.get!(UniverseFlat, universe.id).thumbnails == expected
  end
end
