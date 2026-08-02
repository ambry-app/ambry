defmodule Ambry.Metadata.Providers.WikidataTest do
  use ExUnit.Case, async: false
  use Patch

  alias Ambry.Metadata.Provider
  alias Ambry.Metadata.Providers.Wikidata
  alias Ambry.Metadata.Providers.Wikidata.Client

  @mocks Path.join(__DIR__, "mocks")

  @wikidata_api "https://www.wikidata.org/w/api.php"
  @summary_prefix "https://en.wikipedia.org/api/rest_v1/page/summary/"

  defp fixture(name) do
    @mocks |> Path.join(name) |> File.read!() |> Jason.decode!()
  end

  describe "search_authors/2" do
    test "searches entities, hydrates, and keeps only humans in search order" do
      search = fixture("wikidata_search.json")
      entities = fixture("wikidata_entities_search.json")

      patch(Client, :get_json, fn @wikidata_api, params ->
        case params[:action] do
          "wbsearchentities" -> {:ok, search}
          "wbgetentities" -> {:ok, entities}
        end
      end)

      assert {:ok, authors} = Wikidata.search_authors("ty franck", %{})

      # the novel (non-human) hit is filtered out; humans keep search order
      assert [
               %Provider.Author{
                 provider: "wikidata",
                 id: "Q18608460",
                 name: "Ty Franck",
                 description: "American science fiction writer"
               },
               %Provider.Author{id: "Q99999999", name: "Obscure Narrator"}
             ] = authors

      # all search hits go into one batched hydration call
      assert_called(Client.get_json(@wikidata_api, params))
      assert params[:ids] == "Q18608460|Q3107329|Q99999999"
    end

    test "returns empty list when the search has no hits" do
      patch(Client, :get_json, fn @wikidata_api, _params ->
        {:ok, %{"search" => [], "success" => 1}}
      end)

      assert {:ok, []} = Wikidata.search_authors("zzz", %{})
    end

    test "passes through client errors" do
      patch(Client, :get_json, fn @wikidata_api, _params -> {:error, :nxdomain} end)

      assert {:error, :nxdomain} = Wikidata.search_authors("q", %{})
    end
  end

  describe "author_details/2" do
    test "combines the Wikipedia lead extract with the article's direct original image" do
      details = fixture("wikidata_entity_details.json")
      summary = fixture("wikipedia_summary.json")

      patch(Client, :get_json, fn
        @wikidata_api, _params -> {:ok, details}
        @summary_prefix <> title, [] -> if title == "Ty%20Franck", do: {:ok, summary}
      end)

      assert {:ok, author} = Wikidata.author_details("Q18608460", %{})

      assert %Provider.Author{provider: "wikidata", id: "Q18608460", name: "Ty Franck"} = author
      assert author.description =~ "one half of James S. A. Corey"

      # the summary's originalimage is a direct upload.wikimedia.org file —
      # preferred over Special:FilePath (no redirect / on-demand thumbnailer)
      assert author.image_url ==
               "https://upload.wikimedia.org/wikipedia/commons/8/85/Ty_Franck_%2836166643166%29.jpg"
    end

    test "falls back to the P18 FilePath URL when the summary has no image" do
      details = fixture("wikidata_entity_details.json")
      summary = fixture("wikipedia_summary.json") |> Map.drop(["originalimage", "thumbnail"])

      patch(Client, :get_json, fn
        @wikidata_api, _params -> {:ok, details}
        @summary_prefix <> _title, [] -> {:ok, summary}
      end)

      assert {:ok, author} = Wikidata.author_details("Q18608460", %{})

      # P18 filename → scaled Special:FilePath URL, fully encoded
      assert author.image_url ==
               "https://commons.wikimedia.org/wiki/Special:FilePath/Ty%20Franck%20%2836166643166%29.jpg?width=1200"
    end

    test "falls back to the Wikidata description when there is no English article" do
      details = fixture("wikidata_entity_details_no_article.json")

      patch(Client, :get_json, fn @wikidata_api, _params -> {:ok, details} end)

      assert {:ok, author} = Wikidata.author_details("Q99999999", %{})

      assert author.description == "audiobook narrator"
      assert author.image_url == nil
    end

    test "a failing summary fetch degrades to the Wikidata description and P18 image" do
      details = fixture("wikidata_entity_details.json")

      patch(Client, :get_json, fn
        @wikidata_api, _params -> {:ok, details}
        @summary_prefix <> _title, [] -> {:error, :not_found}
      end)

      assert {:ok, author} = Wikidata.author_details("Q18608460", %{})
      assert author.description == "American science fiction writer"
      assert author.image_url =~ "Special:FilePath"
    end

    test "missing entities are :not_found" do
      patch(Client, :get_json, fn @wikidata_api, _params ->
        {:ok, %{"entities" => %{"Q0" => %{"id" => "Q0", "missing" => ""}}, "success" => 1}}
      end)

      assert {:error, :not_found} = Wikidata.author_details("Q0", %{})
    end
  end
end
