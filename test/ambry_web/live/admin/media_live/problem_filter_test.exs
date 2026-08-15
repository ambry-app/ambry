defmodule AmbryWeb.Admin.MediaLive.ProblemFilterTest do
  @moduledoc """
  The overview counts recordings that need something done to them, and a
  count the operator can't open is half an answer. These are the lists those
  counts link to.
  """
  use AmbryWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  setup :register_and_log_in_admin_user

  test "narrows to recordings whose files couldn't be read", %{conn: conn} do
    insert(:media,
      book: build(:book, title: "Broken"),
      missing_since: DateTime.utc_now(:second)
    )

    insert(:media, book: build(:book, title: "Fine"))

    {:ok, _view, html} = live(conn, ~p"/admin/audiobooks?problem=missing")

    assert html =~ "Broken"
    refute html =~ "Fine"
  end

  test "narrows to recordings that can only be streamed", %{conn: conn} do
    :media
    |> build(book: build(:book, title: "Legacy"))
    |> insert()

    :media
    |> build(book: build(:book, title: "Direct"))
    |> with_tracks()
    |> insert()

    {:ok, _view, html} = live(conn, ~p"/admin/audiobooks?problem=streaming")

    assert html =~ "Legacy"
    refute html =~ "Direct"
  end

  test "says which list this is, and offers the way out", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/audiobooks?problem=missing")

    assert has_element?(view, "[data-role='problem-filter']", "Files couldn't be read")
    assert has_element?(view, "[data-role='problem-filter'][href='/admin/audiobooks']")
  end

  # "No audiobooks yet. Create one." is a lie under a filter, and it offers
  # the one action that has nothing to do with why the page is empty.
  test "an empty filtered list says what it means", %{conn: conn} do
    insert(:media, book: build(:book, title: "Fine"))

    {:ok, _view, html} = live(conn, ~p"/admin/audiobooks?problem=missing")

    assert html =~ "Every audiobook&#39;s files are where they should be."
    refute html =~ "No audiobooks yet"
  end

  # A filter arriving from another page has to survive the page's own
  # controls, or a search inside it quietly widens to the whole library.
  test "searching within a filtered list keeps the filter", %{conn: conn} do
    insert(:media,
      book: build(:book, title: "Broken Thing"),
      missing_since: DateTime.utc_now(:second)
    )

    insert(:media, book: build(:book, title: "Broken Nothing"))

    {:ok, view, _html} = live(conn, ~p"/admin/audiobooks?problem=missing")

    html =
      view
      |> form("form[phx-submit='search']", search: %{query: "Broken"})
      |> render_submit()

    assert html =~ "Broken Thing"
    refute html =~ "Broken Nothing"
    assert has_element?(view, "[data-role='problem-filter']")
  end

  test "an unknown problem is ignored rather than emptying the page", %{conn: conn} do
    insert(:media, book: build(:book, title: "Fine"))

    {:ok, view, html} = live(conn, ~p"/admin/audiobooks?problem=nonsense")

    assert html =~ "Fine"
    refute has_element?(view, "[data-role='problem-filter']")
  end
end
