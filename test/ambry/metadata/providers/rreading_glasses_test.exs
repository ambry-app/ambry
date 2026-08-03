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
        _base, "/book/bulk?" <> _query, [] -> {:ok, bulk}
      end)

      assert {:ok, [first | _rest] = books} = RreadingGlasses.search_books("dcc", %{})

      # every search bookId must reach /book/bulk as its own repeated `id=`
      # param, hand-built into the path: the endpoint drops all-but-first id
      # in csv form, and Req's :params option collapses duplicate keys
      search_ids = search |> Enum.map(& &1["bookId"]) |> Enum.uniq()
      expected_path = "/book/bulk?" <> Enum.map_join(search_ids, "&", &"id=#{&1}")
      assert_called(Client.get_json(_, ^expected_path, []))

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

  describe "published dates" do
    # Book.published means the work's ORIGINAL publication date, never a
    # specific edition's (ROADMAP hard rule)
    test "prefers the work-level date over the chosen edition's" do
      work = %{
        "ForeignId" => 1,
        "Title" => "The Martian",
        "ReleaseDateRaw" => "2011-09-27",
        "BestBookId" => 5,
        "Books" => [%{"ForeignId" => 5, "ReleaseDateRaw" => "2014-02-11", "ImageUrl" => "x"}]
      }

      patch(Client, :get_json, fn _base, "/work/1", [] -> {:ok, work} end)

      assert {:ok, %Provider.Book{published: published}} = RreadingGlasses.book_details("1", %{})
      assert %Provider.PublishedDate{date: ~D[2011-09-27], display_format: :full} = published
    end

    test "falls back to the earliest edition date when the work carries none" do
      work = %{
        "ForeignId" => 1,
        "Title" => "Undated Work",
        "ReleaseDateRaw" => "",
        "BestBookId" => 5,
        "Books" => [
          %{"ForeignId" => 5, "ReleaseDateRaw" => "2014-02-11", "ImageUrl" => "x"},
          %{"ForeignId" => 6, "ReleaseDateRaw" => "2011-09-27"},
          %{"ForeignId" => 7}
        ]
      }

      patch(Client, :get_json, fn _base, "/work/1", [] -> {:ok, work} end)

      assert {:ok, %Provider.Book{published: published}} = RreadingGlasses.book_details("1", %{})
      assert %Provider.PublishedDate{date: ~D[2011-09-27]} = published
    end

    test "no date at all yields nil" do
      work = %{
        "ForeignId" => 1,
        "Title" => "Undated Work",
        "Books" => [%{"ForeignId" => 5}]
      }

      patch(Client, :get_json, fn _base, "/work/1", [] -> {:ok, work} end)

      assert {:ok, %Provider.Book{published: nil}} = RreadingGlasses.book_details("1", %{})
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

    test "orders results by name similarity to the query, not book-hit order" do
      # first search hit is a book *about* Doyle by his bibliographer;
      # Doyle himself authors the remaining hits
      search = [
        %{"bookId" => 1, "workId" => 10, "author" => %{"id" => 111}},
        %{"bookId" => 2, "workId" => 20, "author" => %{"id" => 222}},
        %{"bookId" => 3, "workId" => 30, "author" => %{"id" => 222}}
      ]

      patch(Client, :get_json, fn
        _base, "/search", _params ->
          {:ok, search}

        _base, "/author/111", [] ->
          {:ok, %{"ForeignId" => 111, "Name" => "Richard Lancelyn Green"}}

        _base, "/author/222", [] ->
          {:ok, %{"ForeignId" => 222, "Name" => "Arthur Conan Doyle"}}
      end)

      assert {:ok, [first, second]} = RreadingGlasses.search_authors("arthur conan doyle", %{})
      assert first.name == "Arthur Conan Doyle"
      assert second.name == "Richard Lancelyn Green"
    end

    test "strips Goodreads size modifiers from author photos" do
      author = fixture("rreading_glasses_author.json")
      assert author["ImageUrl"] =~ "._UY200_"

      patch(Client, :get_json, fn _base, "/author/" <> _id, [] -> {:ok, author} end)

      assert {:ok, %Provider.Author{image_url: image_url}} =
               RreadingGlasses.author_details("999015", %{})

      refute image_url =~ "._UY200_"
      assert image_url =~ ~r/999015\.jpg$/
    end

    test "maps the Goodreads nophoto placeholder to no image" do
      author = %{
        "ForeignId" => 1,
        "Name" => "Richard Lancelyn Green",
        "ImageUrl" =>
          "https://i.gr-assets.com/images/S/compressed.photo.goodreads.com/nophoto/user/u_700x933.png"
      }

      patch(Client, :get_json, fn _base, "/author/" <> _id, [] -> {:ok, author} end)

      assert {:ok, %Provider.Author{image_url: nil}} = RreadingGlasses.author_details("1", %{})
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
