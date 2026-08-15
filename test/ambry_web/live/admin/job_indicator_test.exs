defmodule AmbryWeb.Admin.JobIndicatorTest do
  @moduledoc """
  The ambient background-work indicator in the admin header.

  The moment an operator most wants to know whether the server is working is
  while they are somewhere else, so the interesting assertions here are the
  ones made against pages that are not the overview.
  """
  use AmbryWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  setup :register_and_log_in_admin_user

  # Not the overview: the overview has a whole section about the queues, and
  # a test that only ever looks there would pass with the header widget
  # wired to nothing.
  @elsewhere ["/admin/books", "/admin/inbox", "/admin/audiobooks", "/admin/settings"]

  test "a quiet server still renders the indicator, so it can be trusted", %{conn: conn} do
    for path <- @elsewhere do
      {:ok, view, _html} = live(conn, path)

      assert has_element?(view, "[data-role='job-indicator']", "Idle"),
             "expected the idle job indicator on #{path}"

      refute has_element?(view, "[data-role='job-indicator-failed']")
    end
  end

  test "it says what is running, on every admin page", %{conn: conn} do
    insert_job(queue: "metadata", state: "executing")
    insert_job(queue: "metadata", state: "executing")

    for path <- @elsewhere do
      {:ok, view, _html} = live(conn, path)

      assert has_element?(view, "[data-role='job-indicator']", "2 running"),
             "expected the running count on #{path}"
    end
  end

  test "queued and retrying are named rather than folded into running", %{conn: conn} do
    insert_job(queue: "media", state: "available")

    {:ok, view, _html} = live(conn, "/admin/books")
    assert has_element?(view, "[data-role='job-indicator']", "1 queued")

    insert_job(queue: "metadata", state: "retryable")

    {:ok, view, _html} = live(conn, "/admin/books")
    assert has_element?(view, "[data-role='job-indicator']", "1 queued")

    # Running outranks both: what the server is doing beats what it is about to.
    insert_job(queue: "metadata", state: "executing")

    {:ok, view, _html} = live(conn, "/admin/books")
    assert has_element?(view, "[data-role='job-indicator']", "1 running")
  end

  test "busy and broken are different answers and both are shown", %{conn: conn} do
    insert_job(queue: "metadata", state: "executing")
    insert_job(queue: "media", state: "discarded", discarded_at: ~N[2026-08-01 00:00:00])
    insert_job(queue: "media", state: "cancelled", cancelled_at: ~N[2026-08-01 00:00:00])

    {:ok, view, _html} = live(conn, "/admin/books")

    assert has_element?(view, "[data-role='job-indicator']", "1 running")
    assert has_element?(view, "[data-role='job-indicator-failed']", "2")
  end

  test "it opens Oban in a new tab rather than taking the page you are on", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/admin/books")

    assert has_element?(
             view,
             "[data-role='job-indicator'][href='/admin/oban'][target='_blank']"
           )
  end

  # `Oban.Plugins.Lifeline` exists because of exactly this: an `executing` row
  # left by a node that died counts as work in flight forever, and the pruner
  # only ever touches finished jobs.
  test "the plugin that rescues orphaned jobs is configured" do
    plugins = :ambry |> Application.get_env(Oban, []) |> Keyword.fetch!(:plugins)

    assert {Oban.Plugins.Lifeline, opts} =
             Enum.find(plugins, &match?({Oban.Plugins.Lifeline, _}, &1))

    # Longer than any legitimate job, because Lifeline rescues by age alone
    # and running an import twice would place the same files twice.
    assert opts[:rescue_after] >= to_timeout(hour: 1)
  end
end
