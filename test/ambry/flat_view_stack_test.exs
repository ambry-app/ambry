defmodule Ambry.FlatViewStackTest do
  @moduledoc """
  The admin list cover-stacks (books/series/universes flat views) follow the
  same part-set rules as the user-facing tiles — one cover per edition, a
  part set contributes its first part, a sole-edition part set stacks all
  its parts — but deliberately include non-ready media (admin lists are ops
  views).
  """
  use Ambry.DataCase

  alias Ambry.Books.BookFlat
  alias Ambry.Books.SeriesFlat
  alias Ambry.Books.UniverseFlat
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

  test "a part set contributes only its first part when other editions exist" do
    book = insert(:book)
    group = insert(:recording_group)

    solo = insert_media_with_cover(book, "solo", status: :ready, published: ~D[2020-01-01])

    [part_one, _part_two, _part_three] =
      for n <- 1..3 do
        insert_media_with_cover(book, "part#{n}",
          part_number: n,
          parts_total: 3,
          recording_group: group,
          status: :ready,
          published: ~D[2021-01-01]
        )
      end

    flat = Repo.get!(BookFlat, book.id)

    # newest edition first (published desc): the set's first part, then solo
    assert flat.thumbnails == [small_thumb(part_one), small_thumb(solo)]
  end

  test "a sole part-set edition stacks all of its parts in part order" do
    book = insert(:book)
    group = insert(:recording_group)

    parts =
      for n <- [2, 1, 3] do
        insert_media_with_cover(book, "part#{n}",
          part_number: n,
          parts_total: 3,
          recording_group: group,
          status: :ready
        )
      end

    flat = Repo.get!(BookFlat, book.id)

    expected =
      parts
      |> Enum.sort_by(& &1.part_number)
      |> Enum.map(&small_thumb/1)

    assert flat.thumbnails == expected
  end

  test "non-ready media still contribute covers (admin lists are ops views)" do
    book = insert(:book)
    pending = insert_media_with_cover(book, "pending", status: :pending)

    flat = Repo.get!(BookFlat, book.id)

    assert flat.thumbnails == [small_thumb(pending)]
  end

  test "series and universe rows apply the same per-book collapse" do
    series = insert(:series)
    universe = insert(:universe)

    book =
      insert(:book,
        series_books: [%{series: series, book_number: 1}],
        book_universes: [%{universe: universe}]
      )

    group = insert(:recording_group)

    solo = insert_media_with_cover(book, "solo", status: :ready, published: ~D[2020-01-01])

    [part_one | _rest] =
      for n <- 1..2 do
        insert_media_with_cover(book, "part#{n}",
          part_number: n,
          parts_total: 2,
          recording_group: group,
          status: :ready,
          published: ~D[2021-01-01]
        )
      end

    assert Repo.get!(SeriesFlat, series.id).thumbnails ==
             [small_thumb(part_one), small_thumb(solo)]

    assert Repo.get!(UniverseFlat, universe.id).thumbnails ==
             [small_thumb(part_one), small_thumb(solo)]
  end
end
