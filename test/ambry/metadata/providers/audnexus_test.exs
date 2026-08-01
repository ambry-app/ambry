defmodule Ambry.Metadata.Providers.AudnexusTest do
  use ExUnit.Case, async: false
  use Patch

  alias Ambry.Metadata.Provider
  alias Ambry.Metadata.Providers.Audnexus

  test "normalizes author search results" do
    patch(AmbryScraping.Audnexus, :search_authors, fn "matt" ->
      {:ok, [%AmbryScraping.Audnexus.Author{id: "B002D1TN2W", name: "Matt Dinniman"}]}
    end)

    assert {:ok,
            [%Provider.Author{id: "B002D1TN2W", name: "Matt Dinniman", provider: "audnexus"}]} =
             Audnexus.search_authors("matt", %{})
  end

  test "normalizes author details" do
    patch(AmbryScraping.Audnexus, :author_details, fn "B002D1TN2W" ->
      {:ok,
       %AmbryScraping.Audnexus.AuthorDetails{
         id: "B002D1TN2W",
         name: "Matt Dinniman",
         description: "Writer and artist.",
         image: "https://images.audible.com/author.jpg"
       }}
    end)

    assert {:ok, %Provider.Author{} = author} = Audnexus.author_details("B002D1TN2W", %{})
    assert author.description == "Writer and artist."
    assert author.image_url == "https://images.audible.com/author.jpg"
  end

  test "normalizes chapters" do
    patch(AmbryScraping.Audnexus, :book_chapters, fn "B08BKGYQXW" ->
      {:ok,
       %AmbryScraping.Audnexus.Chapters{
         asin: "B08BKGYQXW",
         brand_intro_duration_ms: 2043,
         brand_outro_duration_ms: 5061,
         chapters: [
           %AmbryScraping.Audnexus.Chapter{
             title: "Chapter 1",
             start_offset_ms: 0,
             start_offset_sec: 0,
             length_ms: 1_800_000
           }
         ]
       }}
    end)

    assert {:ok, %Provider.Chapters{asin: "B08BKGYQXW", chapters: [chapter]}} =
             Audnexus.chapters("B08BKGYQXW", %{})

    assert %Provider.Chapter{title: "Chapter 1", start_offset_ms: 0, length_ms: 1_800_000} =
             chapter
  end

  test "passes through not_found" do
    patch(AmbryScraping.Audnexus, :book_chapters, fn _asin -> {:error, :not_found} end)

    assert {:error, :not_found} = Audnexus.chapters("B000", %{})
  end
end
