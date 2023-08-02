defmodule AmbryWeb.PersonLiveTest do
  use AmbryWeb.ConnCase

  import Phoenix.LiveViewTest

  setup :register_and_log_in_user

  test "renders a person show page with authored books", %{conn: conn} do
    %{book_authors: [%{author: %{person: %{id: person_id, name: person_name}}} | _]} = insert(:book)

    {:ok, _view, html} = live(conn, ~p"/people/#{person_id}")
    assert html =~ escape(person_name)
  end

  test "renders a person show page with narrated books", %{conn: conn} do
    %{media_narrators: [%{narrator: %{person: %{id: person_id} = person}} | _]} = insert(:media)
    {:ok, %{name: person_name}} = Ambry.People.update_person(person, %{name: "Foo"})

    {:ok, _view, html} = live(conn, ~p"/people/#{person_id}")
    assert html =~ escape(person_name)
  end
end
