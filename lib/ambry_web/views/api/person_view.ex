defmodule AmbryWeb.API.PersonView do
  use AmbryWeb, :view

  alias AmbryWeb.API.{BookView, PersonView}

  def render("show.json", %{person: person}) do
    %{data: render_one(person, PersonView, "person.json")}
  end

  def render("person.json", %{person: person}) do
    %{
      id: person.id,
      name: person.name,
      description: person.description,
      imagePath: person.image_path,
      authors:
        Enum.map(person.authors, fn author ->
          %{
            id: author.id,
            name: author.name,
            books: render_many(author.books, BookView, "book_index.json")
          }
        end),
      narrators:
        Enum.map(person.narrators, fn narrator ->
          %{
            id: narrator.id,
            name: narrator.name,
            books: render_many(narrator.books, BookView, "book_index.json")
          }
        end)
    }
  end
end
