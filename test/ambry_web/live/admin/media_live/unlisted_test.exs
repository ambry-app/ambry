defmodule AmbryWeb.Admin.MediaLive.UnlistedTest do
  @moduledoc """
  Unlisted recordings are invisible everywhere users browse, so the admin
  list is the one place that has to say so.
  """
  use AmbryWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  setup :register_and_log_in_admin_user

  test "badges an unlisted recording", %{conn: conn} do
    insert(:media, book: build(:book), status: :ready, unlisted_at: DateTime.utc_now(:second))

    {:ok, _view, html} = live(conn, ~p"/admin/audiobooks")

    assert html |> Floki.parse_document!() |> Floki.find("[data-role='media-unlisted']") != []
    assert html =~ "unlisted"
  end

  test "leaves a listed recording unbadged", %{conn: conn} do
    insert(:media, book: build(:book), status: :ready, unlisted_at: nil)

    {:ok, _view, html} = live(conn, ~p"/admin/audiobooks")

    assert html |> Floki.parse_document!() |> Floki.find("[data-role='media-unlisted']") == []
  end

  test "the form checkbox unlists and relists without churning the timestamp", %{conn: conn} do
    media = insert(:media, book: build(:book))

    {:ok, view, _html} = live(conn, ~p"/admin/audiobooks/#{media.id}/edit")

    view
    |> form("#media-form", %{"media" => %{"unlisted" => "true"}})
    |> render_submit()

    assert %{unlisted_at: %DateTime{} = hidden_at} = Ambry.Media.get_media!(media.id)

    {:ok, view, _html} = live(conn, ~p"/admin/audiobooks/#{media.id}/edit")
    assert has_element?(view, "input#media-unlisted[checked]")

    view
    |> form("#media-form", %{"media" => %{"unlisted" => "true"}})
    |> render_submit()

    assert %{unlisted_at: ^hidden_at} = Ambry.Media.get_media!(media.id)

    {:ok, view, _html} = live(conn, ~p"/admin/audiobooks/#{media.id}/edit")

    view
    |> form("#media-form", %{"media" => %{"unlisted" => "false"}})
    |> render_submit()

    assert %{unlisted_at: nil} = Ambry.Media.get_media!(media.id)
  end

  test "?problem=unlisted narrows the list to unlisted recordings", %{conn: conn} do
    listed = insert(:media, book: build(:book), status: :ready)

    unlisted =
      insert(:media, book: build(:book), status: :ready, unlisted_at: DateTime.utc_now(:second))

    {:ok, _view, html} = live(conn, ~p"/admin/audiobooks?problem=unlisted")

    assert html =~ html_escape(unlisted.book.title)
    refute html =~ html_escape(listed.book.title)
    assert html =~ "Hidden from browsing"
  end
end
