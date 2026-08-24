defmodule AmbryWeb.Admin.ReturnToTest do
  @moduledoc """
  Coming back from a form lands on the record that was saved.

  Only the server's half is here. Spending the `?focus=` afterwards is the
  hook's own business and leaves no trace on this side — see
  `assets/js/hooks/focus-row.js`.
  """
  use AmbryWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias AmbryWeb.Admin.ReturnTo

  setup :register_and_log_in_admin_user

  describe "arriving with a focus" do
    test "hands the record to the hook that lights it up", %{conn: conn} do
      book = Ambry.Factory.insert(:book)

      {:ok, _view, html} = live(conn, ~p"/admin/books?focus=#{book.id}")

      assert html =~ ~s|data-focus="#{book.id}"|
      assert html =~ ~s|id="row-#{book.id}"|
    end

    test "a list arrived at without one has nothing to light", %{conn: conn} do
      Ambry.Factory.insert(:book)

      {:ok, _view, html} = live(conn, ~p"/admin/books")

      refute html =~ "data-focus=\""
    end
  end

  describe "query/2" do
    test "keeps the list state a list actually reads" do
      assert ReturnTo.query(%{filter: "gibson", page: 3, sort: "title"}) ==
               %{"filter" => "gibson", "page" => "3", "sort" => "title"}
    end

    test "drops the defaults, so a plain list has a plain address" do
      assert ReturnTo.query(%{filter: nil, page: 1, sort: nil}) == %{}
    end

    test "drops anything a list does not read" do
      assert ReturnTo.query(%{filter: "x", secret: "y"}) == %{"filter" => "x"}
    end
  end

  describe "path/3" do
    test "names the record so the list can find it again" do
      assert ReturnTo.path("/admin/books", %{"page" => "3"}, 42) ==
               "/admin/books?focus=42&page=3"
    end

    test "a form reached from nowhere goes back to the bare list" do
      assert ReturnTo.path("/admin/books", %{}) == "/admin/books"
    end
  end
end
