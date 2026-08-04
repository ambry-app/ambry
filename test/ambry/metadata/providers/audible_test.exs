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

    # The provider now sends structured params rather than one string:
    # Audible's catalog matches `title` against the title alone.
    patch(AmbryScraping.Audible, :search_books, fn %{keywords: "dcc"}, _opts ->
      {:ok, [product]}
    end)

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

  # The bug this exists to prevent: the catalog's `title` parameter matches
  # against the title alone, so a concatenated "title author" string found
  # nothing at all — which is why the inbox's whole recording level came up
  # empty on every item.
  test "sends a structured query as separate parameters" do
    patch(AmbryScraping.Audible, :search_books, fn params, _opts ->
      send(self(), {:params, params})
      {:ok, []}
    end)

    query = %Provider.Query{
      title: "Neuromancer",
      author: "William Gibson",
      narrator: "Jeff Harding"
    }

    assert {:ok, []} = Audible.search_books(query, %{})

    assert_received {:params,
                     %{title: "Neuromancer", author: "William Gibson", narrator: "Jeff Harding"}}
  end

  # Every parameter is an AND filter, so the most precise query is the most
  # fragile: asking for a narrator the only catalogued edition doesn't have
  # returns nothing rather than the edition that exists.
  test "widens the query until something comes back" do
    patch(AmbryScraping.Audible, :search_books, fn params, _opts ->
      send(self(), {:tried, Map.keys(params) |> Enum.sort()})
      if Map.has_key?(params, :narrator), do: {:ok, []}, else: {:ok, [product()]}
    end)

    query = %Provider.Query{title: "Neuromancer", author: "William Gibson", narrator: "Nobody"}
    assert {:ok, [_book]} = Audible.search_books(query, %{})

    assert_received {:tried, [:author, :narrator, :title]}
    assert_received {:tried, [:author, :title]}
  end

  # A failure is not an empty result — widening past it would hide an outage
  # behind a vaguer query that happens to succeed.
  test "does not widen past a failure" do
    patch(AmbryScraping.Audible, :search_books, fn _params, _opts -> {:error, :rate_limited} end)

    query = %Provider.Query{title: "Neuromancer", author: "William Gibson", narrator: "Somebody"}
    assert {:error, :rate_limited} = Audible.search_books(query, %{})
  end

  defp product do
    %AmbryScraping.Audible.Product{
      id: "B0057HR4E6",
      title: "Neuromancer",
      authors: [],
      narrators: [],
      series: [],
      published: ~D[2011-06-30],
      language: "english"
    }
  end
end
