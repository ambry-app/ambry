defmodule AmbryWeb.Admin.MediaLive.ReplaceTest do
  use AmbryWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  setup :register_and_log_in_admin_user

  describe "Replace" do
    setup do
      media =
        :media
        |> build(book: build(:book))
        |> with_source_files()
        |> insert()

      %{media: media}
    end

    test "renders the disruption warning and the current source files", %{
      conn: conn,
      media: media
    } do
      {:ok, _view, html} = live(conn, ~p"/admin/media/#{media}/replace")

      assert html =~ "Replacing audio is disruptive"
      assert html =~ "Current audio file(s)"
      assert html =~ Path.basename(hd(media.source_files))
    end

    test "shows an error when submitting with no files", %{conn: conn, media: media} do
      {:ok, view, _html} = live(conn, ~p"/admin/media/#{media}/replace")

      html =
        view
        |> form("form", media: %{processor: ""})
        |> render_submit()

      assert html =~ "You must provide at least one audio file"
    end
  end
end
