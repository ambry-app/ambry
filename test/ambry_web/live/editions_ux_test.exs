defmodule AmbryWeb.EditionsUxTest do
  @moduledoc """
  Behavioral spec for tile system v2 (ROADMAP "Tile system v2"): recursive
  collapse, ready-only for users, editions-based click targets.
  """
  use AmbryWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  setup :register_and_log_in_user

  defp insert_part_set(book, opts \\ []) do
    group = insert(:recording_group, name: opts[:name])

    for n <- 1..Keyword.get(opts, :count, 3) do
      insert(:media,
        book: book,
        part_number: n,
        parts_total: Keyword.get(opts, :count, 3),
        recording_group: group,
        status: :ready,
        published: opts[:published]
      )
    end
  end

  describe "library page" do
    test "a group renders as one stacked tile navigating to its first part", %{conn: conn} do
      book = insert(:book, title: "Dungeon Crawler Carl")
      [part_one, part_two, part_three] = insert_part_set(book, name: "Season One")

      {:ok, _view, html} = live(conn, ~p"/")

      assert html =~ "Dungeon Crawler Carl"
      assert html =~ "3 parts"
      refute html =~ "Season One"
      refute html =~ "(Part 1 of 3)"

      # group tiles land on the first part — never the book page
      assert html =~ ~p"/audiobooks/#{part_one.id}"
      refute html =~ ~p"/books/#{book.id}"

      for part <- [part_two, part_three] do
        refute html =~ ~p"/audiobooks/#{part.id}"
      end
    end

    test "single-release media are unaffected", %{conn: conn} do
      book = insert(:book, title: "Standalone Book")
      insert(:media, book: book, status: :ready)

      {:ok, _view, html} = live(conn, ~p"/")

      assert html =~ "Standalone Book"
    end
  end

  describe "book page" do
    test "renders a flat grid of edition tiles — groups stack, no sub-sections", %{conn: conn} do
      book = insert(:book, title: "Dungeon Crawler Carl")
      [part_one, _part_two] = insert_part_set(book, name: "Season One", count: 2)
      solo = insert(:media, book: book, status: :ready)

      {:ok, _view, html} = live(conn, ~p"/books/#{book.id}")

      assert html =~ "Editions"
      assert html =~ "2 parts"
      refute html =~ "Season One"

      # the group is ONE tile linking to its first part; parts are not
      # individually tiled
      assert html =~ ~p"/audiobooks/#{part_one.id}"
      assert html =~ ~p"/audiobooks/#{solo.id}"
      refute html =~ "Part 2 of 2"
    end

    test "a book whose only edition is a group redirects to the first part", %{conn: conn} do
      book = insert(:book)
      [part_one | _rest] = insert_part_set(book)

      assert {:error, {:live_redirect, %{to: to}}} = live(conn, ~p"/books/#{book.id}")
      assert to == ~p"/audiobooks/#{part_one.id}"
    end

    test "a book with nothing ready redirects home", %{conn: conn} do
      book = insert(:book)
      insert(:media, book: book, status: :pending)

      assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/books/#{book.id}")
    end
  end

  describe "audiobook page" do
    test "a sibling group is one stacked tile under Other Editions, landing on its first part",
         %{conn: conn} do
      book = insert(:book, title: "Dungeon Crawler Carl")
      [part_one, part_two, part_three] = insert_part_set(book, name: "Season One")
      solo = insert(:media, book: book, status: :ready)

      {:ok, _view, html} = live(conn, ~p"/audiobooks/#{solo.id}")

      assert html =~ "Other Editions"
      assert html =~ "3 parts"
      assert html =~ ~p"/audiobooks/#{part_one.id}"

      for part <- [part_two, part_three] do
        refute html =~ ~p"/audiobooks/#{part.id}"
      end
    end

    test "a sibling group with non-ready parts stacks only its ready parts", %{conn: conn} do
      book = insert(:book)
      group = insert(:recording_group)

      insert(:media,
        book: book,
        part_number: 1,
        parts_total: 3,
        recording_group: group,
        status: :pending
      )

      [part_two, _part_three] =
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
      assert html =~ ~p"/audiobooks/#{part_two.id}"
    end

    test "shows the part rail and excludes siblings from Other Editions", %{conn: conn} do
      book = insert(:book, title: "Dungeon Crawler Carl")
      [part_one, part_two, _part_three] = insert_part_set(book, name: "Season One")
      other_edition = insert(:media, book: book, status: :ready, publisher: "Solo Narration Inc")

      {:ok, _view, html} = live(conn, ~p"/audiobooks/#{part_two.id}")

      # rail with heading and links to sibling parts (no show_label opt-in,
      # so the group name stays hidden)
      assert html =~ "3 parts"
      refute html =~ "Season One"
      assert html =~ ~p"/audiobooks/#{part_one.id}"

      # the true alternate edition still shows under Other Editions
      assert html =~ "Other Editions"
      assert html =~ ~p"/audiobooks/#{other_edition.id}"

      # sibling parts appear exactly once (in the rail)
      assert html |> String.split(~p"/audiobooks/#{part_one.id}") |> length() == 2
    end

    test "a lone sibling part stays in the rail, not Other Editions", %{conn: conn} do
      # regression: book.media excludes the current media, so a 2-part set
      # leaves ONE sibling — which collapses to a single edition (one-part
      # groups present as singles) and used to leak into Other Editions
      book = insert(:book)
      [part_one, part_two] = insert_part_set(book, count: 2)

      {:ok, _view, html} = live(conn, ~p"/audiobooks/#{part_one.id}")

      refute html =~ "Other Editions"
      # the sibling links exactly once — from the rail
      assert html |> String.split(~p"/audiobooks/#{part_two.id}") |> length() == 2
    end

    test "no rail or Other Editions for a lone single-part recording", %{conn: conn} do
      book = insert(:book)
      media = insert(:media, book: book, status: :ready)

      {:ok, _view, html} = live(conn, ~p"/audiobooks/#{media.id}")

      refute html =~ "Other Editions"
    end
  end

  describe "series page (book tiles)" do
    test "a sole-group book links into its first part; multi-edition books to the book page",
         %{conn: conn} do
      series = insert(:series, name: "Test Series")

      sole_group_book =
        insert(:book, title: "Sole Group Book", series_books: [%{series: series, book_number: 1}])

      [part_one | _rest] = insert_part_set(sole_group_book)

      multi_book =
        insert(:book,
          title: "Multi Edition Book",
          series_books: [%{series: series, book_number: 2}]
        )

      insert(:media, book: multi_book, status: :ready)
      insert(:media, book: multi_book, status: :ready)

      {:ok, _view, html} = live(conn, ~p"/series/#{series.id}")

      # editions-based click rule: one edition → its target (the group's
      # first part), multiple → the book page
      assert html =~ ~p"/audiobooks/#{part_one.id}"
      assert html =~ ~p"/books/#{multi_book.id}"
      refute html =~ ~p"/books/#{sole_group_book.id}"
    end

    test "books with nothing ready are hidden entirely", %{conn: conn} do
      series = insert(:series)

      visible =
        insert(:book, title: "Visible Book", series_books: [%{series: series, book_number: 1}])

      insert(:media, book: visible, status: :ready)

      hidden =
        insert(:book, title: "Hidden Book", series_books: [%{series: series, book_number: 2}])

      insert(:media, book: hidden, status: :pending)

      {:ok, _view, html} = live(conn, ~p"/series/#{series.id}")

      assert html =~ "Visible Book"
      refute html =~ "Hidden Book"
    end
  end

  describe "narrator page" do
    test "never shows non-ready media", %{conn: conn} do
      narrator = insert(:narrator, person: build(:person))

      ready =
        insert(:media,
          book: insert(:book, title: "Ready Book"),
          status: :ready,
          media_narrators: [build(:media_narrator, narrator: narrator)]
        )

      pending =
        insert(:media,
          book: insert(:book, title: "Pending Book"),
          status: :pending,
          media_narrators: [build(:media_narrator, narrator: narrator)]
        )

      {:ok, _view, html} = live(conn, ~p"/narrators/#{narrator.id}")

      assert html =~ ~p"/audiobooks/#{ready.id}"
      refute html =~ ~p"/audiobooks/#{pending.id}"
    end
  end

  describe "group label visibility" do
    test "the label renders on group tiles only when the group opts in", %{conn: conn} do
      book = insert(:book, title: "Dungeon Crawler Carl")

      group =
        insert(:recording_group,
          name: "The Audio Immersion Experience — Season One",
          show_label: true
        )

      [part_one | _rest] =
        for n <- 1..2 do
          insert(:media,
            book: book,
            part_number: n,
            parts_total: 2,
            recording_group: group,
            status: :ready
          )
        end

      other = insert(:media, book: book, status: :ready)

      # library group tile shows the label
      {:ok, _view, html} = live(conn, ~p"/")
      assert html =~ "The Audio Immersion Experience — Season One"

      # book page group tile shows it too
      {:ok, _view, html} = live(conn, ~p"/books/#{book.id}")
      assert html =~ "The Audio Immersion Experience — Season One"

      # the audiobook page rail heading shows it under the same opt-in
      {:ok, _view, html} = live(conn, ~p"/audiobooks/#{part_one.id}")
      assert html =~ "The Audio Immersion Experience — Season One"

      # sanity: another edition exists so the book page didn't redirect
      assert other.status == :ready
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

      # library: the group tile counts in episodes
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
end
