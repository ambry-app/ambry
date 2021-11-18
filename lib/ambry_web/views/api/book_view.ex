defmodule AmbryWeb.API.BookView do
  use AmbryWeb, :view

  alias Ambry.Books.Book
  alias Ambry.Series.SeriesBook
  alias AmbryWeb.API.BookView

  def render("index.json", %{books: books, has_more?: has_more?}) do
    %{
      data: render_many(books, BookView, "book_index.json"),
      hasMore: has_more?
    }
  end

  def render("show.json", %{book: book}) do
    %{data: render_one(book, BookView, "book_show.json")}
  end

  def render("book_index.json", %{book: book}) do
    book_common(book)
  end

  def render("book_show.json", %{book: book}) do
    book
    |> book_common()
    |> Map.merge(book_details(book))
  end

  defp book_common(%SeriesBook{book: book, book_number: book_number}) do
    Map.merge(book_common(book), %{bookNumber: book_number})
  end

  defp book_common(%Book{} = book) do
    %{
      id: book.id,
      title: book.title,
      imagePath: book.image_path,
      authors:
        book
        |> authors()
        |> Enum.map(fn author ->
          %{
            id: author.id,
            personId: author.person_id,
            name: author.name
          }
        end),
      series:
        book.series_books
        |> Enum.sort_by(& &1.series.name)
        |> Enum.map(fn series_book ->
          %{
            id: series_book.series.id,
            name: series_book.series.name,
            bookNumber: series_book.book_number
          }
        end)
    }
  end

  defp book_details(%SeriesBook{book: book}), do: book_details(book)

  defp book_details(%Book{} = book) do
    %{
      description: book.description,
      published: book.published,
      media:
        Enum.map(book.media, fn media ->
          duration = Decimal.to_float(media.duration)

          %{
            id: media.id,
            abridged: media.abridged,
            fullCast: media.full_cast,
            duration: duration,
            narrators:
              Enum.map(media.narrators, fn narrator ->
                %{
                  personId: narrator.person_id,
                  name: narrator.name
                }
              end)
          }
        end)
    }
  end

  defp authors(%Book{authors: authors}) when is_list(authors), do: authors

  defp authors(%Book{book_authors: book_authors}) when is_list(book_authors),
    do: Enum.map(book_authors, & &1.author)
end
