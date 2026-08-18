defmodule AmbryWeb.Admin.IndexRowTest do
  @moduledoc """
  The anatomy every admin list row shares (docs/admin-design-language.md §3a).

  These are the guarantees that no per-surface test can see, and that ten
  hand-built row slots drifted away from once already.
  """
  use AmbryWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Ambry.Books.SeriesBookType
  alias AmbryWeb.Admin.Components

  setup :register_and_log_in_admin_user

  # The library lists made the whole row clickable with `JS.navigate` on the
  # div, which is a target but not a link; the queue linked only its title,
  # which is a link but a 200px target. The stretched `::after` is both.
  test "a row's headline is a real link that covers the card", %{conn: conn} do
    media = insert(:media, book: build(:book))

    {:ok, view, _html} = live(conn, ~p"/admin/audiobooks")

    assert view
           |> element("a[href='/admin/audiobooks/#{media.id}/edit'].after\\:absolute")
           |> has_element?()
  end

  # LiveView dispatches a click to the *closest* phx-click ancestor, so a row
  # whose destination is a `phx-click` on the container fires it as well as
  # any anchor nested inside — which is how clicking Devices also navigated
  # to Playthroughs.
  test "no row carries its destination as a phx-click on the container", %{conn: conn} do
    user = insert(:user)
    insert(:media, book: build(:book))

    for path <- [~p"/admin/audiobooks", ~p"/admin/books", ~p"/admin/people", ~p"/admin/users"] do
      {:ok, _view, html} = live(conn, path)

      refute html =~ ~s(phx-click="[[&quot;navigate&quot;)
    end

    {:ok, _view, html} = live(conn, ~p"/admin/users/#{user}/devices")
    refute html =~ ~s(phx-click="[[&quot;patch&quot;)
  end

  # The container hardcoded `cursor-pointer` on every row whether or not it
  # had anywhere to go, so the queue and this list invited clicks on dead
  # space.
  test "a row with nowhere to go is not a link and wears no pointer", %{conn: conn} do
    user = insert(:user)
    device = insert(:device, type: :web, browser: "Firefox", os_name: "Linux")
    insert(:device_user, device: device, user: user)

    {:ok, _html_doc, rows} = rows(conn, ~p"/admin/users/#{user}/devices")

    assert rows != []

    for row <- rows do
      assert Floki.find(row, "a") == []
      refute row |> Floki.attribute("class") |> to_string() =~ "cursor-pointer"
    end
  end

  # Every list's actions are worded buttons now: the exception that let index
  # rows go icon-only was written for a five-verb media row whose verbs have
  # all since moved onto the form.
  test "row actions carry words, not bare glyphs", %{conn: conn} do
    insert(:media, book: build(:book))

    {:ok, _view, html} = live(conn, ~p"/admin/audiobooks")

    assert html =~ "Edit"
    assert html =~ "Delete"
  end

  # The rail is two buttons wide and the actions wrap into it, so four verbs
  # are a 2 x 2 rather than a four-storey column. Stacking one per line was
  # tried and is worse: tall, and ragged down the left.
  test "an action rail wraps, it never stacks one per line", %{conn: conn} do
    insert(:media, book: build(:book))
    insert(:user)

    for path <- [~p"/admin/audiobooks", ~p"/admin/users", ~p"/admin/inbox"] do
      {:ok, _doc, rails} = find(conn, path, "[data-role='row-actions']")

      for rail <- rails do
        classes = rail |> Floki.attribute("class") |> to_string()

        assert classes =~ "flex-wrap"
        refute classes =~ "flex-col"
      end
    end
  end

  # 224px was sized for a pair: Playthroughs (120px) beside Devices (86px) is
  # the tightest, and "Import record" (124px) beside Edit is the longest
  # single label. A label past that rags the rail on whatever list grows it,
  # which is the failure this budget exists to catch. Characters are a proxy
  # for pixels, which is the best a server-side test can do.
  @label_budget 13

  test "no action label is longer than the rail was sized for", %{conn: conn} do
    insert(:media, book: build(:book))
    insert(:user)
    insert(:book)
    insert(:person)

    paths = [
      ~p"/admin/audiobooks",
      ~p"/admin/books",
      ~p"/admin/people",
      ~p"/admin/users",
      ~p"/admin/inbox"
    ]

    labels =
      Enum.flat_map(paths, fn path ->
        {:ok, _doc, rails} = find(conn, path, "[data-role='row-actions']")

        for rail <- rails, action <- Floki.find(rail, "a, span[role='button']") do
          {path, action |> Floki.text() |> String.trim()}
        end
      end)

    # Or the loop below passes by finding nothing, which is how a budget stops
    # being a budget.
    assert length(labels) > 10

    for {path, label} <- labels do
      assert String.length(label) <= @label_budget,
             "#{path}: #{inspect(label)} is wider than the rail was sized for"
    end
  end

  # "Added", "Imported", "Joined", "Last seen" — a record of what the app did.
  # A duration and a publication date are facts about the work, and reading
  # them in the same column made them look like timestamps too.
  test "the footer corner holds system timestamps and nothing else", %{conn: conn} do
    insert(:media, book: build(:book), duration: Decimal.new("3600"))

    {:ok, _doc, footers} = find(conn, ~p"/admin/audiobooks", "[data-role='row-footer']")

    assert footers != []

    for footer <- footers do
      text = footer |> Floki.text() |> String.trim()

      assert text =~ ~r/^Added /
      refute text =~ "Duration"
      refute text =~ "Published"
    end
  end

  # A GraphicAudio cast runs to a dozen people, and a row that prints all
  # twelve buries the title it was meant to help identify.
  test "a row credits the first narrator and counts the rest", %{conn: conn} do
    insert(:media,
      book: build(:book),
      media_narrators: [
        build(:media_narrator,
          narrator: build(:narrator, name: "Karen Foley", person: build(:person))
        ),
        build(:media_narrator,
          narrator: build(:narrator, name: "Eric Messner", person: build(:person))
        ),
        build(:media_narrator,
          narrator: build(:narrator, name: "Melody Muze", person: build(:person))
        )
      ]
    )

    {:ok, _view, html} = live(conn, ~p"/admin/audiobooks")

    assert html =~ "Read by Karen Foley and 2 others"
    refute html =~ "Melody Muze"
  end

  # In words a person reads, not the cells these were on the way out of the
  # footer ("8/30/22", "14:04:02"), which is the shape a spreadsheet wants.
  # `record_meta/1` is one helper, so the audiobooks list and the queue's
  # imported rows cannot phrase the same facts differently again.
  test "the meta line reads as a sentence, with the publisher in it", %{conn: conn} do
    series = insert(:series)
    book = insert(:book, series_books: [build(:series_book, series: series, book_number: 1)])

    insert(:media,
      book: book,
      published: ~D[2022-08-30],
      published_format: :full,
      publisher: "Recorded Books",
      duration: Decimal.new("117780")
    )

    {:ok, _view, html} = live(conn, ~p"/admin/audiobooks")

    assert html =~
             "#{series.name} #1 · Published August 30, 2022 by Recorded Books · " <>
               "32 hours and 43 minutes"

    refute html =~ "32:43:00"
  end

  # Title, authors and narrators are what every record has, so they are always
  # three lines; the series, the publisher, the date and the duration are each
  # sometimes there, so they share the fourth — and it disappears entirely
  # when a record has none of them. A series owning a line of its own is what
  # made these rows tall.
  describe "the variable line" do
    test "puts the series in front and keeps one order" do
      full = %{
        series: [%SeriesBookType{name: "The Stormlight Archive", number: Decimal.new(1)}],
        published: ~D[2022-08-30],
        published_format: :full,
        publisher: "Recorded Books",
        duration: Decimal.new("117780")
      }

      assert Components.record_meta(full) ==
               "The Stormlight Archive #1 · Published August 30, 2022 by Recorded Books · " <>
                 "32 hours and 43 minutes"
    end

    test "collapses to nothing when nothing varies" do
      bare = %{
        series: [],
        published: nil,
        published_format: nil,
        publisher: nil,
        duration: nil
      }

      assert Components.record_meta(bare) == ""
    end

    # A book has neither of the audiobook-only halves, so the same helper
    # reduces rather than rendering empty joins.
    test "reduces for a record with no publisher and no duration" do
      book = %{
        series: [%SeriesBookType{name: "Mistborn", number: Decimal.new(2)}],
        published: ~D[2007-08-21],
        published_format: :year
      }

      assert Components.record_meta(book) == "Mistborn #2 · Published 2007"
    end
  end

  defp rows(conn, path) do
    find(conn, path, "[class*='rounded-lg'][class*='bg-zinc-900'][class*='p-4']")
  end

  defp find(conn, path, selector) do
    {:ok, _view, html} = live(conn, path)
    document = Floki.parse_document!(html)

    {:ok, document, Floki.find(document, selector)}
  end
end
