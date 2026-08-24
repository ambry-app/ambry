defmodule AmbryWeb.Admin.WatchLive.FormTest do
  use AmbryWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Ambry.Wanted

  setup :register_and_log_in_admin_user

  defp watch do
    {:ok, watch} =
      Wanted.create_watch(%{
        provider: "audible",
        provider_id: "B0FKVNLXQS",
        expected_release_date: ~D[2026-09-29],
        edition: %{
          title: "A Book Not Out Yet",
          authors: ["An Author"],
          narrators: ["A Narrator"],
          publisher: "A Publisher",
          duration_seconds: 36_000
        }
      })

    watch
  end

  describe "saving" do
    test "returns to the list and highlights the row it saved", %{conn: conn} do
      watch = watch()

      {:ok, view, _html} = live(conn, ~p"/admin/watches/#{watch}/edit")

      {:ok, _list, html} =
        view
        |> form("#watch-form", watch: %{expected_release_date: "2026-10-30"})
        |> render_submit()
        |> follow_redirect(conn, ~p"/admin/watches?focus=#{watch.id}")

      assert html =~ "A Book Not Out Yet"
    end

    test "the list it returns to says what it saved, and still says it saved",
         %{conn: conn} do
      watch = watch()

      {:ok, view, _html} = live(conn, ~p"/admin/watches/#{watch}/edit")

      {:ok, _list, html} =
        view
        |> form("#watch-form", watch: %{expected_release_date: "2026-10-30"})
        |> render_submit()
        |> follow_redirect(conn, ~p"/admin/watches?focus=#{watch.id}")

      assert html =~ ~s|data-focus="#{watch.id}"|
      assert html =~ "Saved."
    end
  end
end
