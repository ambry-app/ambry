defmodule AmbryWeb.PartSetUxTest do
  use AmbryWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias AmbryWeb.CoreComponents

  setup :register_and_log_in_user

  defp insert_part_set(book, opts \\ []) do
    group = insert(:recording_group, name: opts[:name])

    for n <- 1..Keyword.get(opts, :count, 3) do
      insert(:media,
        book: book,
        part_number: n,
        parts_total: Keyword.get(opts, :count, 3),
        recording_group: group,
        status: :ready
      )
    end
  end

  describe "library page" do
    test "collapses a part set into one stacked tile linking to the book", %{conn: conn} do
      book = insert(:book, title: "Dungeon Crawler Carl")
      insert_part_set(book, name: "Season One")

      {:ok, _view, html} = live(conn, ~p"/")

      assert html =~ "Dungeon Crawler Carl"
      assert html =~ "3 parts"
      refute html =~ "Season One"
      # the individual part labels don't appear as separate tiles
      refute html =~ "(Part 1 of 3)"
      assert html =~ ~p"/books/#{book.id}"
    end

    test "single-release media are unaffected", %{conn: conn} do
      book = insert(:book, title: "Standalone Book")
      insert(:media, book: book, status: :ready)

      {:ok, _view, html} = live(conn, ~p"/")

      assert html =~ "Standalone Book"
    end
  end

  describe "book page" do
    test "renders part sets as titled sections with parts in order, ungrouped below", %{
      conn: conn
    } do
      book = insert(:book, title: "Dungeon Crawler Carl")
      insert_part_set(book, name: "Season One", count: 2)
      insert(:media, book: book, status: :ready)

      {:ok, _view, html} = live(conn, ~p"/books/#{book.id}")

      assert html =~ "Editions"
      assert html =~ "2 parts"
      refute html =~ "Season One"

      # parts render in part order despite publication-date ordering elsewhere
      assert [i1, i2] =
               Regex.scan(~r/Part \d of 2/, html) |> List.flatten() |> Enum.take(2)

      assert i1 == "Part 1 of 2"
      assert i2 == "Part 2 of 2"
    end
  end

  describe "audiobook page" do
    test "a sibling part set stacks as one tile under Other Editions", %{conn: conn} do
      book = insert(:book, title: "Dungeon Crawler Carl")
      [part_one, part_two, part_three] = insert_part_set(book, name: "Season One")
      solo = insert(:media, book: book, status: :ready)

      {:ok, _view, html} = live(conn, ~p"/audiobooks/#{solo.id}")

      # one stacked tile for the whole set, landing on the book page —
      # never one tile per part
      assert html =~ "Other Editions"
      assert html =~ "3 parts"
      assert html =~ ~p"/books/#{book.id}"

      for part <- [part_one, part_two, part_three] do
        refute html =~ ~p"/audiobooks/#{part.id}"
      end
    end

    test "a sibling set with non-ready parts stacks only its ready parts", %{conn: conn} do
      book = insert(:book)
      group = insert(:recording_group)

      insert(:media,
        book: book,
        part_number: 1,
        parts_total: 3,
        recording_group: group,
        status: :pending
      )

      for n <- 2..3 do
        insert(:media,
          book: book,
          part_number: n,
          parts_total: 3,
          recording_group: group,
          status: :ready
        )
      end

      solo = insert(:media, book: book, status: :ready)

      {:ok, _view, html} = live(conn, ~p"/audiobooks/#{solo.id}")

      # the pending first part neither counts nor represents
      assert html =~ "2 parts"
    end

    test "shows the part rail and excludes siblings from Other Editions", %{conn: conn} do
      book = insert(:book, title: "Dungeon Crawler Carl")
      [part_one, part_two, _part_three] = insert_part_set(book, name: "Season One")
      other_edition = insert(:media, book: book, status: :ready, publisher: "Solo Narration Inc")

      {:ok, _view, html} = live(conn, ~p"/audiobooks/#{part_two.id}")

      # rail with heading and links to sibling parts (group name is admin-only)
      assert html =~ "3 parts"
      refute html =~ "Season One"
      assert html =~ ~p"/audiobooks/#{part_one.id}"

      # the true alternate edition still shows under Other Editions
      assert html =~ "Other Editions"
      assert html =~ ~p"/audiobooks/#{other_edition.id}"

      # sibling parts are not duplicated in Other Editions: their links appear
      # exactly once (in the rail)
      assert html |> String.split(~p"/audiobooks/#{part_one.id}") |> length() == 2
    end

    test "no rail or Other Editions for a lone single-part recording", %{conn: conn} do
      book = insert(:book)
      media = insert(:media, book: book, status: :ready)

      {:ok, _view, html} = live(conn, ~p"/audiobooks/#{media.id}")

      refute html =~ "Other Editions"
    end
  end

  describe "custom part wording" do
    test "episode wording flows through labels and titles", %{conn: conn} do
      book = insert(:book, title: "Dungeon Crawler Carl")

      group =
        insert(:recording_group,
          name: "Admin Label",
          part_word: "episode",
          part_word_plural: "episodes"
        )

      parts =
        for n <- 1..2 do
          insert(:media,
            book: book,
            part_number: n,
            parts_total: 2,
            recording_group: group,
            status: :ready
          )
        end

      # library: collapsed tile counts in episodes
      {:ok, _view, html} = live(conn, ~p"/")
      assert html =~ "2 episodes"
      refute html =~ "Admin Label"

      # audiobook page: composed title, details line, and rail chips all say Episode
      {:ok, _view, html} = live(conn, ~p"/audiobooks/#{hd(parts).id}")
      assert html =~ "Dungeon Crawler Carl (Episode 1 of 2)"
      assert html =~ "Episode 2"
      refute html =~ "Admin Label"
    end
  end

  describe "part_set_stack_media/1 (book tile stacks)" do
    test "a part set contributes only its first part when other editions exist" do
      book = insert(:book)
      [part_one | rest] = insert_part_set(book)
      solo = insert(:media, book: book, status: :ready)

      stacked = CoreComponents.part_set_stack_media([solo, part_one | rest])

      assert Enum.map(stacked, & &1.id) == [solo.id, part_one.id]
    end

    test "a sole part-set edition stacks all of its parts in order" do
      book = insert(:book)
      parts = insert_part_set(book)

      stacked = CoreComponents.part_set_stack_media(Enum.shuffle(parts))

      assert Enum.map(stacked, & &1.id) == Enum.map(parts, & &1.id)
    end

    test "non-ready media never contribute to stacks" do
      book = insert(:book)
      parts = insert_part_set(book)
      pending = insert(:media, book: book, status: :pending)

      # the pending solo is invisible — the set is still the sole (ready)
      # edition and stacks its parts
      stacked = CoreComponents.part_set_stack_media([pending | parts])

      assert Enum.map(stacked, & &1.id) == Enum.map(parts, & &1.id)
    end

    test "part_set_representatives/1 keeps one ready media per edition" do
      book = insert(:book)
      group = insert(:recording_group)

      pending_first =
        insert(:media, book: book, part_number: 1, recording_group: group, status: :pending)

      ready_second =
        insert(:media, book: book, part_number: 2, recording_group: group, status: :ready)

      solo = insert(:media, book: book, status: :ready)

      representatives =
        CoreComponents.part_set_representatives([pending_first, ready_second, solo])

      # the set is represented by its first READY part
      assert Enum.map(representatives, & &1.id) == [ready_second.id, solo.id]
    end
  end
end
