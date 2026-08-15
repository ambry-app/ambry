defmodule AmbryWeb.Admin.HomeLive.IndexTest do
  use AmbryWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Ambry.Inbox.InboxItem
  alias Ambry.Repo

  setup :register_and_log_in_admin_user

  describe "Index" do
    test "renders every section", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin")

      assert html =~ "Overview"
      assert html =~ "Needs you"
      assert html =~ "Background work"
      assert html =~ "Metadata providers"
      assert html =~ "Library"
    end

    test "an empty install says so rather than showing zeroes", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin")

      assert has_element?(view, "*", "Nothing waiting.")
      assert has_element?(view, "*", "Nothing's wrong.")
      assert has_element?(view, "[data-role='work-words']", "Nothing running.")
      assert has_element?(view, "*", "No job has given up in the last day.")
      assert has_element?(view, "*", "Nothing in the queue has asked a provider yet.")
    end

    test "splits the pending queue into ready and waiting on a decision", %{conn: conn} do
      ready_item("ready-one")
      ready_item("ready-two")
      drafted_item("undecided")

      {:ok, view, _html} = live(conn, ~p"/admin")

      assert has_element?(view, "[data-role='ready-count']", "2")
      assert has_element?(view, "[data-role='decisions-count']", "1")
    end

    test "items nobody has asked about are the machine's backlog, not the operator's",
         %{conn: conn} do
      raw_item("never-asked")

      {:ok, view, _html} = live(conn, ~p"/admin")

      assert has_element?(view, "[data-role='ready-count']", "0")
      assert has_element?(view, "[data-role='decisions-count']", "0")
      assert has_element?(view, "*", "haven't been read yet")
    end

    test "counts a missing recording as a problem, linked to the list of them",
         %{conn: conn} do
      :media
      |> build(book: build(:book), missing_since: DateTime.utc_now(:second))
      |> insert()

      {:ok, view, _html} = live(conn, ~p"/admin")

      assert has_element?(view, "a[href='/admin/audiobooks?problem=missing']", "1")
    end

    test "a legacy recording is a quiet problem, not a cutover progress bar",
         %{conn: conn} do
      :media |> build(book: build(:book)) |> insert()

      {:ok, view, html} = live(conn, ~p"/admin")

      assert has_element?(view, "a[href='/admin/audiobooks?problem=streaming']", "1")
      assert html =~ "Still served by transcoding"
      refute html =~ "2.0"
    end

    test "reports a running job and names the queue it is in", %{conn: conn} do
      insert_job(queue: "metadata", state: "executing")

      {:ok, view, _html} = live(conn, ~p"/admin")

      assert has_element?(view, "[data-role='work-words']", "1 running.")
      assert has_element?(view, "[data-role='queue-line']", "1 running")
    end

    test "a failed job says what failed, not just that something did", %{conn: conn} do
      insert_job(
        queue: "media",
        state: "discarded",
        worker: "Ambry.Inbox.RunImport",
        discarded_at: ~N[2026-08-01 00:00:00],
        errors: [%{"error" => "** (File.Error) could not copy\n    stack"}]
      )

      {:ok, view, _html} = live(conn, ~p"/admin")

      assert has_element?(view, "[data-role='job-failure']", "RunImport")
      assert has_element?(view, "[data-role='job-failure']", "could not copy")
    end

    test "reports how the providers have been answering", %{conn: conn} do
      raw_item("matched", %{
        matches: %{
          "work" => %{
            "providers" => [
              %{"id" => "audible", "name" => "Audible", "status" => "ok", "count" => 2},
              %{
                "id" => "hardcover:details",
                "name" => "Hardcover details",
                "status" => "failed",
                "count" => 0,
                "reason" => "429"
              }
            ]
          }
        }
      })

      {:ok, view, _html} = live(conn, ~p"/admin")

      assert has_element?(view, "[data-role='provider-health']", "Audible")
      assert has_element?(view, "[data-role='provider-health']", "1 call")
      assert has_element?(view, "[data-role='provider-health']", "Hardcover details")
      assert has_element?(view, "[data-role='provider-health']", "1 of 1 failed")
    end

    test "keeps the inventory strip", %{conn: conn} do
      person1 = :person |> build() |> with_thumbnails() |> insert()
      person2 = :person |> build() |> with_thumbnails() |> insert()

      author = insert(:author, person: person1)
      narrator = insert(:narrator, person: person2)
      series = insert(:series)

      book =
        insert(:book,
          book_authors: [%{author: author}],
          series_books: [%{series: series, book_number: 1}]
        )

      :media
      |> build(status: :ready, book: book, media_narrators: [%{narrator: narrator}])
      |> with_thumbnails()
      |> insert()

      {:ok, view, _html} = live(conn, ~p"/admin")

      assert has_element?(view, "[data-role='author-count']", "1")
      assert has_element?(view, "[data-role='narrator-count']", "1")
      assert has_element?(view, "[data-role='book-count']", "1")
      assert has_element?(view, "[data-role='series-count']", "1")
      assert has_element?(view, "[data-role='media-count']", "1")
      assert has_element?(view, "[data-role='user-count']", "1")
    end

    test "updates in realtime when data changes", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin")

      assert has_element?(view, "[data-role='author-count']", "0")

      %{author_people: [%{person: person}]} = insert(:author, person: build(:person))
      person |> Ambry.People.PubSub.PersonCreated.new() |> Ambry.PubSub.broadcast()
      ensure_all_messages_handled(view.pid)

      assert has_element?(view, "[data-role='author-count']", "1")
    end

    test "the nav badge counts the pending queue and only appears when there is one",
         %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin")
      refute html =~ "inbox-pending-badge"

      raw_item("waiting")

      {:ok, view, _html} = live(conn, ~p"/admin")
      assert has_element?(view, "[data-role='inbox-pending-badge']", "1")
    end
  end

  defp raw_item(path, attrs \\ %{}) do
    attrs =
      attrs
      |> Map.merge(%{path: path, status: :pending})
      |> Map.put_new_lazy(:source_id, fn -> insert(:source).id end)

    %InboxItem{} |> InboxItem.changeset(attrs) |> Repo.insert!()
  end

  defp drafted_item(path) do
    path |> raw_item() |> InboxItem.put_draft(%{}) |> Repo.update!()
  end

  defp ready_item(path) do
    path |> drafted_item() |> Ecto.Changeset.change(ready: true) |> Repo.update!()
  end

  # Straight into the table: `discarded` is a state Oban will not insert.
  defp insert_job(attrs) do
    defaults = %{
      state: "available",
      queue: "default",
      worker: "Ambry.Inbox.RunProbe",
      args: %{},
      errors: [],
      attempt: 0,
      max_attempts: 20,
      inserted_at: ~N[2026-08-01 00:00:00],
      scheduled_at: ~N[2026-08-01 00:00:00]
    }

    Repo.insert_all("oban_jobs", [Map.merge(defaults, Map.new(attrs))])
  end
end
