defmodule AmbryWeb.PersonLiveTest do
  use AmbryWeb.ConnCase

  import Phoenix.LiveViewTest

  setup :register_and_log_in_user

  test "renders a person show page", %{conn: conn} do
    %{id: person_id, name: person_name} = insert(:person)

    {:ok, _view, html} = live(conn, ~p"/people/#{person_id}")
    assert html =~ escape(person_name)
  end
end
