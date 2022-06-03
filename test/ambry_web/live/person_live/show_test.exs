defmodule AmbryWeb.PersonLive.ShowTest do
  use AmbryWeb.ConnCase

  setup :register_and_log_in_user

  test "renders a person show page", %{conn: conn} do
    %{id: person_id, name: person_name} = insert(:person)

    {:ok, _view, html} = live(conn, "/people/#{person_id}")
    assert html =~ escape(person_name)
  end
end
