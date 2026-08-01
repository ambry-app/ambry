defmodule Ambry.Metadata.Providers.RreadingGlassesTest do
  use ExUnit.Case, async: false
  use Patch

  alias Ambry.Metadata.Provider
  alias Ambry.Metadata.Providers.RreadingGlasses
  alias Ambry.Metadata.Providers.RreadingGlasses.Client

  @mocks Path.join(__DIR__, "mocks")

  defp fixture(name) do
    @mocks |> Path.join(name) |> File.read!() |> Jason.decode!()
  end

  describe "search_books/2" do
    test "searches, hydrates via bulk, and normalizes in search order" do
      search = fixture("rreading_glasses_search.json")
      bulk = fixture("rreading_glasses_bulk.json")

      patch(Client, :get_json, fn
        _base, "/search", _params -> {:ok, search}
        _base, "/book/bulk", _params -> {:ok, bulk}
      end)

      assert {:ok, [first | _rest] = books} = RreadingGlasses.search_books("dcc", %{})

      # only hydrated works come back, deduped by work id
      assert length(books) == length(Enum.uniq_by(books, & &1.id))
      assert %Provider.Book{provider: "rreading_glasses", title: "Dungeon Crawler Carl"} = first
      assert [%Provider.Contributor{name: "Matt Dinniman", role: "author"}] = first.authors
      assert [%Provider.Series{name: "Dungeon Crawler Carl", number: "1"}] = first.series
      assert first.cover_url =~ "http"
      assert %Provider.PublishedDate{display_format: :full} = first.published
      assert Enum.all?(first.editions, &match?(%Provider.Edition{}, &1))
    end

    test "returns empty list when search has no results" do
      patch(Client, :get_json, fn _base, "/search", _params -> {:ok, []} end)

      assert {:ok, []} = RreadingGlasses.search_books("zzz", %{})
    end

    test "passes through client errors" do
      patch(Client, :get_json, fn _base, "/search", _params ->
        {:error, :unexpected_response_payload}
      end)

      assert {:error, :unexpected_response_payload} = RreadingGlasses.search_books("q", %{})
    end
  end

  describe "book_details/2" do
    test "fetches a work and normalizes it with editions" do
      work = fixture("rreading_glasses_work.json")

      patch(Client, :get_json, fn _base, "/work/76027608", [] -> {:ok, work} end)

      assert {:ok, %Provider.Book{} = book} = RreadingGlasses.book_details("76027608", %{})
      assert book.id == "76027608"
      assert book.title == "Dungeon Crawler Carl"
      assert book.asin
      assert [%Provider.Series{number: "1"} | _] = book.series
      refute book.editions == []
    end
  end

  describe "search_authors/2" do
    test "hydrates distinct author ids from book search" do
      search = fixture("rreading_glasses_search.json")
      author = fixture("rreading_glasses_author.json")

      patch(Client, :get_json, fn
        _base, "/search", _params -> {:ok, search}
        _base, "/author/" <> _id, [] -> {:ok, author}
      end)

      assert {:ok, [%Provider.Author{} = result]} = RreadingGlasses.search_authors("dcc", %{})
      assert result.name == "Matt Dinniman"
      assert result.provider == "rreading_glasses"
      assert result.image_url =~ "http"
    end
  end

  describe "author_details/2" do
    test "normalizes an author payload" do
      author = fixture("rreading_glasses_author.json")

      patch(Client, :get_json, fn _base, "/author/999015", [] -> {:ok, author} end)

      assert {:ok, %Provider.Author{id: "999015", name: "Matt Dinniman"}} =
               RreadingGlasses.author_details("999015", %{})
    end

    test "returns not_found from the client" do
      patch(Client, :get_json, fn _base, _path, [] -> {:error, :not_found} end)

      assert {:error, :not_found} = RreadingGlasses.author_details("0", %{})
    end
  end

  describe "config" do
    test "declares a base_url field defaulting to the public instance" do
      assert [%Provider.ConfigField{key: :base_url, default: "https://api.bookinfo.pro"}] =
               RreadingGlasses.config_fields()
    end
  end
end
