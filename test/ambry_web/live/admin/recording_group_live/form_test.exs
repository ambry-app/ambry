defmodule AmbryWeb.Admin.RecordingGroupLive.FormTest do
  use AmbryWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Ambry.Media

  setup :register_and_log_in_admin_user

  describe "New" do
    test "creates a group with members, exactly like a series with books", %{conn: conn} do
      book = insert(:book)
      media_one = insert(:media, book: book)
      media_two = insert(:media, book: book)

      {:ok, view, _html} = live(conn, ~p"/admin/sets/new")

      view
      |> form("#group-form")
      |> render_submit(%{
        recording_group_form: %{
          name: "Season One",
          book_id: to_string(book.id),
          parts_total: "2",
          part_word: "episode",
          members: %{
            "0" => %{media_id: to_string(media_one.id), part_number: "1"},
            "1" => %{media_id: to_string(media_two.id), part_number: "2"}
          }
        }
      })

      assert_returns_to_sets(view)

      {[group], false} = Media.list_recording_groups()
      assert %{name: "Season One", parts_total: 2, part_word: "episode"} = group

      assert Enum.map(group.media, &{&1.id, &1.part_number}) ==
               [{media_one.id, 1}, {media_two.id, 2}]
    end

    test "a group may start empty", %{conn: conn} do
      book = insert(:book)
      {:ok, view, _html} = live(conn, ~p"/admin/sets/new")

      view
      |> form("#group-form")
      |> render_submit(%{
        recording_group_form: %{name: "Awaiting Parts", book_id: to_string(book.id)}
      })

      assert_returns_to_sets(view)

      {[group], false} = Media.list_recording_groups()
      assert %{name: "Awaiting Parts", media: []} = group
    end

    test "refuses a blank name", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/sets/new")

      html =
        view
        |> form("#group-form")
        |> render_submit(%{recording_group_form: %{name: ""}})

      assert html =~ "can&#39;t be blank"
      assert Media.count_recording_groups() == 0
    end
  end

  describe "Edit" do
    test "renders existing members as editable rows", %{conn: conn} do
      book = insert(:book, title: "A Court of Thorns and Roses")
      group = insert(:recording_group, name: "GraphicAudio", parts_total: 2, book: book)
      media = insert(:media, book: book, part_number: 1, recording_group: group)

      {:ok, _view, html} = live(conn, ~p"/admin/sets/#{group.id}/edit")

      doc = Floki.parse_document!(html)

      assert doc
             |> Floki.find(~s{input[name="recording_group_form[members][0][part_number]"]})
             |> Floki.attribute("value") == ["1"]

      assert doc
             |> Floki.find(~s{input[name="recording_group_form[members][0][media_id]"]})
             |> Floki.attribute("value") == [to_string(media.id)]
    end

    # Regression: the member picker's options follow the posted book_id, but
    # the edit page renders the book as static text (posts nothing) — so any
    # keystroke in any field used to leave it scoped to no book at all, and
    # a drop-down whose options went away cannot name what it holds.
    test "editing another field leaves the member pickers displaying their picks", %{
      conn: conn
    } do
      book = insert(:book, title: "A Court of Thorns and Roses")
      group = insert(:recording_group, name: "Graphic Audio", book: book)
      insert(:media, book: book, part_number: 1, recording_group: group)

      {:ok, view, html} = live(conn, ~p"/admin/sets/#{group.id}/edit")

      assert resolver_display(html) == "A Court of Thorns and Roses (Part 1)"

      html =
        view
        |> form("#group-form")
        |> render_change(%{recording_group_form: %{name: "Renamed"}})

      assert resolver_display(html) == "A Court of Thorns and Roses (Part 1)"
    end

    # A drop-down cannot lose what it holds — the option list is the book's
    # audiobooks, so the held one is in it by construction. Worth pinning
    # anyway: the typeahead this replaced *could*, because the label composes
    # a part suffix onto the title and no column holds "A Court of Thorns and
    # Roses (Part 1 of 2)", so opening the box searched for exactly that and
    # said "No matches" about the recording it was holding.
    test "a member picker offers every audiobook of the book, held one included", %{conn: conn} do
      book = insert(:book, title: "A Court of Thorns and Roses")
      group = insert(:recording_group, name: "Graphic Audio", book: book, parts_total: 2)
      held = insert(:media, book: book, part_number: 1, recording_group: group)
      sibling = insert(:media, book: book, part_number: 2, recording_group: group)

      {:ok, view, _html} = live(conn, ~p"/admin/sets/#{group.id}/edit")

      html =
        view
        |> element("#recording_group_form_members_0_media_id-trigger")
        |> render_click()

      refute html =~ "Nothing to choose from"
      assert html =~ ~s(phx-value-id="#{held.id}")
      assert html =~ ~s(phx-value-id="#{sibling.id}")
    end

    # A drop-down lists its options in one fixed order — part 1, 2, 3 — so
    # unlike the typeahead this replaced it does not pin what it holds to the
    # top. It does not need to: the closed trigger names it, and the open
    # list marks it.
    test "the held recording is the one marked as held", %{conn: conn} do
      book = insert(:book, title: "A Court of Thorns and Roses")
      group = insert(:recording_group, name: "Graphic Audio", book: book, parts_total: 3)
      _first = insert(:media, book: book, part_number: 1, recording_group: group)
      _second = insert(:media, book: book, part_number: 2, recording_group: group)
      third = insert(:media, book: book, part_number: 3, recording_group: group)

      {:ok, view, _html} = live(conn, ~p"/admin/sets/#{group.id}/edit")

      # the third member's box holds part 3, which the list orders last
      html =
        view
        |> element("#recording_group_form_members_2_media_id-trigger")
        |> render_click()

      options =
        html
        |> Floki.parse_document!()
        |> Floki.find("#recording_group_form_members_2_media_id-list li[role='option']")

      marked = Enum.filter(options, &(Floki.attribute(&1, "aria-selected") == ["true"]))

      assert marked |> List.first() |> Floki.attribute("phx-value-id") == [to_string(third.id)]

      # and it is the only one carrying the chosen mark
      assert Enum.count(options, &(Floki.find(&1, ".fa-check") != [])) == 1
      assert Enum.count(options, &(Floki.attribute(&1, "aria-selected") == ["true"])) == 1
    end

    # The one credit a picker of audiobooks can be asked to disambiguate by,
    # and the row listed everything except it.
    test "a member picker's rows name the author", %{conn: conn} do
      author = insert(:author, name: "Sarah J. Maas")

      book =
        insert(:book, title: "A Court of Thorns and Roses", book_authors: [%{author: author}])

      group = insert(:recording_group, name: "Graphic Audio", book: book)
      insert(:media, book: book, part_number: 1, recording_group: group)

      {:ok, view, _html} = live(conn, ~p"/admin/sets/#{group.id}/edit")

      html =
        view
        |> element("#recording_group_form_members_0_media_id-trigger")
        |> render_click()

      assert html =~ "Sarah J. Maas"
    end

    # A GraphicAudio cast runs to a dozen people, and a row that prints all
    # twelve buries the title it was meant to help identify.
    test "a picker row credits the first narrator and counts the rest", %{conn: conn} do
      book = insert(:book, title: "A Court of Thorns and Roses")
      group = insert(:recording_group, name: "Graphic Audio", book: book)

      insert(:media,
        book: book,
        part_number: 1,
        recording_group: group,
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

      {:ok, view, _html} = live(conn, ~p"/admin/sets/#{group.id}/edit")

      html =
        view
        |> element("#recording_group_form_members_0_media_id-trigger")
        |> render_click()

      assert html =~ "read by Karen Foley and 2 others"
      refute html =~ "Melody Muze"
    end

    # The detail line already carries five facts, so where a recording sits
    # rides the label's own line instead, muted.
    test "a picker row trails its series on the label line", %{conn: conn} do
      series = insert(:series, name: "A Court of Thorns and Roses")

      book =
        insert(:book,
          title: "A Court of Thorns and Roses",
          series_books: [build(:series_book, series: series, book_number: 1)]
        )

      group = insert(:recording_group, name: "Graphic Audio", book: book)
      insert(:media, book: book, part_number: 1, recording_group: group)

      {:ok, view, _html} = live(conn, ~p"/admin/sets/#{group.id}/edit")

      html =
        view
        |> element("#recording_group_form_members_0_media_id-trigger")
        |> render_click()

      assert html =~ "A Court of Thorns and Roses #1"
    end

    test "saving edits facts and the member list together", %{conn: conn} do
      book = insert(:book)
      group = insert(:recording_group, name: "Before", book: book)
      keep = insert(:media, book: book, part_number: 1, recording_group: group)
      drop = insert(:media, book: book, part_number: 2, recording_group: group)

      {:ok, view, _html} = live(conn, ~p"/admin/sets/#{group.id}/edit")

      # removal is the drop checkbox, same mechanics as dropping a series book
      view
      |> form("#group-form")
      |> render_submit(%{
        recording_group_form: %{
          name: "After",
          show_label: "true",
          members_drop: ["1"]
        }
      })

      assert_returns_to_sets(view)

      updated = Media.get_recording_group!(group.id)
      assert %{name: "After", show_label: true} = updated
      assert Enum.map(updated.media, & &1.id) == [keep.id]

      dropped = Media.get_media!(drop.id)
      assert dropped.recording_group_id == nil
      assert dropped.part_number == nil
    end
  end

  # What the closed drop-down says it is holding.
  defp resolver_display(html) do
    html
    |> Floki.parse_document!()
    |> Floki.find("#recording_group_form_members_0_media_id-trigger span")
    |> List.first()
    |> Floki.text()
    |> String.trim()
  end

  # Saving returns to the sets list naming the record it saved, so the list can
  # scroll to it and light it up. It used to be a bare `/admin/sets` — the
  # front of an unfiltered, default-sorted page one, whoever you were and
  # wherever you had been.
  defp assert_returns_to_sets(view) do
    {path, _flash} = assert_redirect(view)
    %{path: path, query: query} = URI.parse(path)

    assert path == "/admin/sets"
    assert %{"focus" => focus} = URI.decode_query(query || "")
    assert focus != ""
  end
end
