defmodule Ambry.Metadata.Providers.AudibleTest do
  use ExUnit.Case, async: false
  use Patch

  alias Ambry.Metadata.Provider
  alias Ambry.Metadata.Providers.Audible

  test "normalizes catalog products into Book structs" do
    product = %AmbryScraping.Audible.Product{
      id: "B08BKGYQXW",
      title: "Dungeon Crawler Carl",
      authors: [%AmbryScraping.Audible.Author{id: "B002D1TN2W", name: "Matt Dinniman"}],
      narrators: [%AmbryScraping.Audible.Narrator{name: "Jeff Hays"}],
      series: [
        %AmbryScraping.Audible.Series{
          id: "B08X2B5SJ8",
          sequence: "1",
          title: "Dungeon Crawler Carl"
        }
      ],
      description: "The apocalypse will be televised!",
      cover_image: "https://m.media-amazon.com/images/cover.jpg",
      format: "unabridged",
      published: ~D[2020-10-27],
      publisher: "Soundbooth Theater",
      language: "english"
    }

    patch(AmbryScraping.Audible, :search_books, fn "dcc", _opts -> {:ok, [product]} end)

    assert {:ok, [%Provider.Book{} = book]} = Audible.search_books("dcc", %{})

    assert book.provider == "audible"
    assert book.asin == "B08BKGYQXW"
    assert [%Provider.Contributor{name: "Matt Dinniman", role: "author"}] = book.authors
    assert [%Provider.Contributor{name: "Jeff Hays", role: "narrator"}] = book.narrators
    assert [%Provider.Series{name: "Dungeon Crawler Carl", number: "1"}] = book.series
    assert %Provider.PublishedDate{date: ~D[2020-10-27], display_format: :full} = book.published
  end

  test "passes through errors" do
    patch(AmbryScraping.Audible, :search_books, fn _query, _opts -> {:error, :whoops} end)

    assert {:error, :whoops} = Audible.search_books("q", %{})
  end

  test "passes the configured language through, defaulting to english" do
    patch(AmbryScraping.Audible, :search_books, fn _query, opts ->
      send(self(), {:language, Keyword.get(opts, :language)})
      {:ok, []}
    end)

    assert {:ok, []} = Audible.search_books("q", %{})
    assert_received {:language, "english"}

    assert {:ok, []} = Audible.search_books("q", %{language: "german"})
    assert_received {:language, "german"}
  end
end
