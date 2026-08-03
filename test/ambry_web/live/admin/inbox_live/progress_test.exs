defmodule AmbryWeb.Admin.InboxLive.ProgressTest do
  @moduledoc """
  The gap this closes: a row gave no sign of whether its background jobs were
  queued, running, finished or failed. "Why is this row blank?" had no answer
  short of opening the Oban dashboard.
  """
  use AmbryWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Ambry.Inbox.InboxItem
  alias Ambry.Repo

  setup :register_and_log_in_admin_user

  test "says when a row's work is still queued", %{conn: conn} do
    item = item()
    job(item, :available)

    {:ok, _view, html} = live(conn, ~p"/admin/inbox")

    assert progress(html) == ["Queued"]
  end

  test "says when a row is being worked on", %{conn: conn} do
    item = item()
    job(item, :executing)

    {:ok, _view, html} = live(conn, ~p"/admin/inbox")

    assert progress(html) == ["Working on it…"]
  end

  test "says when a row's background job failed", %{conn: conn} do
    item = item()
    job(item, :discarded)

    {:ok, _view, html} = live(conn, ~p"/admin/inbox")

    assert [message] = progress(html)
    assert message =~ "background job failed"
  end

  # Repeating "done" on every settled row is noise that hides the rows that
  # aren't settled — which is the entire point of the feature.
  test "says nothing about a row that's finished", %{conn: conn} do
    item(probe: %{"duration" => 1}, matches: %{"work" => %{}})

    {:ok, _view, html} = live(conn, ~p"/admin/inbox")

    assert progress(html) == []
  end

  # The pruner deletes jobs after a day, so "no job" can't mean "nothing
  # happened" — but an item with nothing to show for itself and no job really
  # did fall through.
  test "flags a row that was never read and has no job to explain it", %{conn: conn} do
    item()

    {:ok, _view, html} = live(conn, ~p"/admin/inbox")

    assert [message] = progress(html)
    assert message =~ "Never read"
  end

  defp item(attrs \\ []) do
    {:ok, item} =
      %InboxItem{}
      |> InboxItem.changeset(
        Enum.into(attrs, %{
          path: "/downloads/release-#{Ecto.UUID.generate()}",
          files: ["/downloads/x/book.m4b"],
          status: :pending
        })
      )
      |> Repo.insert()

    item
  end

  defp job(item, state) do
    Repo.insert_all("oban_jobs", [
      %{
        state: to_string(state),
        queue: "media",
        worker: "Ambry.Inbox.RunProbe",
        args: %{"inbox_item_id" => item.id},
        inserted_at: DateTime.utc_now(:second),
        scheduled_at: DateTime.utc_now(:second)
      }
    ])
  end

  defp progress(html) do
    html
    |> Floki.parse_document!()
    |> Floki.find("[data-role='item-progress']")
    |> Enum.map(&(&1 |> Floki.text() |> String.trim()))
  end
end
