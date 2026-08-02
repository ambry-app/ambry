defmodule Ambry.Metadata.Providers.TmdbTest do
  use ExUnit.Case, async: false
  use Patch

  alias Ambry.Metadata.Provider
  alias Ambry.Metadata.Providers.Tmdb
  alias Ambry.Metadata.Providers.Tmdb.Client

  @mocks Path.join(__DIR__, "mocks")

  defp fixture(name) do
    @mocks |> Path.join(name) |> File.read!() |> Jason.decode!()
  end

  describe "availability" do
    test "unavailable until an API key is configured, with a setup notice" do
      refute Tmdb.available?(%{})
      refute Tmdb.available?(%{api_key: ""})
      assert Tmdb.available?(%{api_key: "abc123"})

      assert [{:info, notice}] = Tmdb.config_notices(%{})
      assert notice =~ "themoviedb.org"
      assert notice =~ "Optional"

      assert [] = Tmdb.config_notices(%{api_key: "abc123"})
    end
  end

  describe "search_authors/2" do
    test "normalizes results with known-for credits as the description" do
      search = fixture("tmdb_search.json")

      patch(Client, :get_json, fn "/search/person", params, _config ->
        assert params[:query] == "ty franck"
        {:ok, search}
      end)

      assert {:ok, [franck, lookalike]} = Tmdb.search_authors("ty franck", %{api_key: "k"})

      assert %Provider.Author{
               provider: "tmdb",
               id: "1252351",
               name: "Ty Franck",
               description: "Writing — The Expanse, Some Film",
               image_url: "https://image.tmdb.org/t/p/original/tyfranck-profile.jpg"
             } = franck

      # no credits and no photo: still listed, just bare
      assert %Provider.Author{id: "555", description: nil, image_url: nil} = lookalike
    end

    test "passes through client errors" do
      patch(Client, :get_json, fn "/search/person", _params, _config ->
        {:error, :unauthorized}
      end)

      assert {:error, :unauthorized} = Tmdb.search_authors("q", %{api_key: "bad"})
    end
  end

  describe "author_details/2" do
    test "returns biography and original-size profile image" do
      person = fixture("tmdb_person.json")

      patch(Client, :get_json, fn "/person/1252351", [], _config -> {:ok, person} end)

      assert {:ok, author} = Tmdb.author_details("1252351", %{api_key: "k"})

      assert %Provider.Author{provider: "tmdb", id: "1252351", name: "Ty Franck"} = author
      assert author.description =~ "one half of James S. A. Corey"
      assert author.image_url == "https://image.tmdb.org/t/p/original/tyfranck-profile.jpg"
    end

    test "empty biography becomes nil" do
      person = fixture("tmdb_person.json") |> Map.put("biography", "")

      patch(Client, :get_json, fn "/person/1252351", [], _config -> {:ok, person} end)

      assert {:ok, %Provider.Author{description: nil}} =
               Tmdb.author_details("1252351", %{api_key: "k"})
    end
  end
end
