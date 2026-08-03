defmodule AmbryWeb.Admin.InboxLive.FormTest do
  use AmbryWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Ambry.Inbox
  alias Ambry.Inbox.Draft
  alias Ambry.Repo

  setup :register_and_log_in_admin_user

  describe "the invariant" do
    test "an unsettled item can't be imported", %{conn: conn} do
      item = probed_item()

      {:ok, view, html} = live(conn, ~p"/admin/inbox/#{item}")

      assert html =~ "Still to settle"
      assert has_element?(view, "button[data-role='import'][disabled]")
    end

    test "a settled item can", %{conn: conn} do
      item = probed_item() |> settle()

      {:ok, view, html} = live(conn, ~p"/admin/inbox/#{item}")

      refute html =~ "Still to settle"
      refute has_element?(view, "button[data-role='import'][disabled]")
    end

    test "importing creates the library records and returns to the queue", %{conn: conn} do
      item = probed_item() |> settle()

      {:ok, view, _html} = live(conn, ~p"/admin/inbox/#{item}")

      view |> element("button[data-role='import']") |> render_click()

      assert %{status: :approved, media_id: media_id} = Inbox.get_item!(item.id)
      assert media_id
    end

    test "each outstanding decision is named, not just counted", %{conn: conn} do
      item = probed_item()

      {:ok, _view, html} = live(conn, ~p"/admin/inbox/#{item}")

      # tag-derived credits are never auto-settled, so the narrators from the
      # fixture's `composer` tag are listed by name
      assert html =~ "Michael Kramer"
      assert html =~ "needs a look"
    end
  end

  describe "settling decisions" do
    test "accept-everything settles what's only waiting on a nod", %{conn: conn} do
      item = probed_item()

      {:ok, view, _html} = live(conn, ~p"/admin/inbox/#{item}")

      html = view |> element("button", "Accept everything") |> render_click()

      refute html =~ "Still to settle"
      assert Inbox.get_item!(item.id).ready
    end

    test "accept-everything never invents a missing required value", %{conn: conn} do
      item = probed_item(dated: false)

      {:ok, view, html} = live(conn, ~p"/admin/inbox/#{item}")
      assert html =~ "First published"

      html = view |> element("button", "Accept everything") |> render_click()

      # the date nobody supplied is still outstanding — this button settles
      # choices, it does not fabricate facts
      assert html =~ "Still to settle"
      assert html =~ "First published"
      refute Inbox.get_item!(item.id).ready
    end

    test "typing a value records it as the operator's, and locks it", %{conn: conn} do
      item = probed_item() |> settle()

      {:ok, view, _html} = live(conn, ~p"/admin/inbox/#{item}")

      view
      |> form("#work-form")
      |> render_change(%{
        "inbox_item" => %{
          "draft" => %{"work" => %{"title" => %{"value" => "A Title I Typed"}}}
        }
      })

      item = Inbox.get_item!(item.id)

      assert item.draft.work.title.value == "A Title I Typed"
      # 1d's lock semantics: editing a value is curation, so it records as the
      # operator's and a later refresh must not overwrite it
      assert item.draft.work.title.source == "manual"
      assert item.draft.work.title.approved
    end

    test "an accepted provider value records that provider, and stays unlocked", %{conn: conn} do
      item = probed_item() |> settle()

      {:ok, view, _html} = live(conn, ~p"/admin/inbox/#{item}")

      view
      |> element(
        "button[phx-click='choose-field'][phx-value-field='title'][phx-value-source='tags']"
      )
      |> render_click()

      item = Inbox.get_item!(item.id)

      assert item.draft.work.title.source == "tags"
      assert item.draft.work.title.approved
    end

    test "a credit can be dropped when the source proposed the wrong person", %{conn: conn} do
      item = probed_item()

      {:ok, view, _html} = live(conn, ~p"/admin/inbox/#{item}")
      before = length(Inbox.get_item!(item.id).draft.recording.narrators)

      view
      |> element(
        "button[phx-click='remove-credit'][phx-value-section='recording'][phx-value-index='0']"
      )
      |> render_click()

      assert length(Inbox.get_item!(item.id).draft.recording.narrators) == before - 1
    end
  end

  describe "credits — credited as / written by" do
    test "the composite case is two people behind one credit", %{conn: conn} do
      item = probed_item()

      {:ok, view, _html} = live(conn, ~p"/admin/inbox/#{item}")

      html =
        view
        |> element(
          "button[phx-click='add-person'][phx-value-section='work'][phx-value-index='0']"
        )
        |> render_click()

      assert html =~ "A shared pen name"

      credit = hd(Inbox.get_item!(item.id).draft.work.authors)
      assert length(credit.people) == 2
    end

    test "naming both people creates one author and two people on import", %{conn: conn} do
      item = probed_item()

      {:ok, view, _html} = live(conn, ~p"/admin/inbox/#{item}")

      view
      |> element("button[phx-click='add-person'][phx-value-section='work'][phx-value-index='0']")
      |> render_click()

      {:ok, item} = Inbox.fetch_item(item.id)

      item =
        update_in(item.draft.work.authors, fn [credit | rest] ->
          [
            %{
              credit
              | name: "James S.A. Corey",
                people: [
                  %Draft.PersonRef{name: "Daniel Abraham"},
                  %Draft.PersonRef{name: "Ty Franck"}
                ]
            }
            | rest
          ]
        end)

      {:ok, item} = Inbox.update_draft(item, Inbox.dump_draft(item.draft))
      item = settle(item)

      assert {:ok, media} = Inbox.approve_item(item)

      book = media.book_id |> Ambry.Books.get_book!() |> Repo.preload(authors: :people)
      assert [author] = book.authors
      assert author.name == "James S.A. Corey"
      assert Enum.map(author.people, & &1.name) |> Enum.sort() == ["Daniel Abraham", "Ty Franck"]
    end

    test "an existing identity is linked rather than duplicated", %{conn: conn} do
      author = insert(:author, name: "Brandon Sanderson")
      item = probed_item()

      {:ok, view, _html} = live(conn, ~p"/admin/inbox/#{item}")

      view
      |> element("#credit-work-0-identity")
      |> render_change(%{
        "section" => "work",
        "index" => "0",
        "identity_id" => to_string(author.id)
      })

      credit = hd(Inbox.get_item!(item.id).draft.work.authors)
      assert credit.mode == :link
      assert credit.identity_id == author.id
    end
  end

  describe "destination" do
    test "says where the file is going before anything is committed", %{conn: conn} do
      item = probed_item() |> settle()

      {:ok, _view, html} = live(conn, ~p"/admin/inbox/#{item}")

      assert html =~ "Referenced where it lies"
      assert html =~ "never move, rename or delete"
    end
  end

  defp probed_item(opts \\ []) do
    name = Keyword.get(opts, :name, "The Way of Kings [M4B]")

    root = Ambry.Paths.source_media_disk_path("watched-#{Ecto.UUID.generate()}")
    release = Path.join(root, name)
    File.mkdir_p!(release)
    File.cp!(tagged_fixture(Keyword.get(opts, :dated, true)), Path.join(release, "book.m4b"))

    {:ok, _counts} = Inbox.discover(root)
    {items, _more} = Inbox.list_items(filter: name)
    {:ok, item} = items |> hd() |> Inbox.probe_item()

    item
  end

  defp tagged_fixture(dated?) do
    dir = Ambry.Paths.source_media_disk_path("tagged-#{Ecto.UUID.generate()}")
    File.mkdir_p!(dir)
    path = Path.join(dir, "tagged.m4b")

    {_output, 0} =
      System.cmd(
        "ffmpeg",
        [
          "-v",
          "quiet",
          "-i",
          valid_audio(:m4a),
          "-c",
          "copy",
          "-metadata",
          "album=The Way of Kings",
          "-metadata",
          "artist=Brandon Sanderson",
          "-metadata",
          "composer=Michael Kramer, Kate Reading"
        ] ++ if(dated?, do: ["-metadata", "date=2010-08-31"], else: []) ++ [path]
      )

    path
  end
end
