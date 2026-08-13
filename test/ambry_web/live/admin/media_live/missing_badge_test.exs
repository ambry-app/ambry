defmodule AmbryWeb.Admin.MediaLive.MissingBadgeTest do
  @moduledoc """
  A nightly sweep whose findings appear nowhere isn't worth running.
  """
  use AmbryWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  setup :register_and_log_in_admin_user

  test "flags a recording whose files have gone missing", %{conn: conn} do
    insert(:media, book: build(:book), status: :ready, missing_since: DateTime.utc_now(:second))

    {:ok, _view, html} = live(conn, ~p"/admin/audiobooks")

    assert html |> Floki.parse_document!() |> Floki.find("[data-role='media-missing']") != []
    assert html =~ "missing"
  end

  # The badge is a statement about the files, not about the recording, so a
  # healthy one mustn't wear it.
  test "leaves a healthy recording unflagged", %{conn: conn} do
    insert(:media, book: build(:book), status: :ready, missing_since: nil)

    {:ok, _view, html} = live(conn, ~p"/admin/audiobooks")

    assert html |> Floki.parse_document!() |> Floki.find("[data-role='media-missing']") == []
  end
end
