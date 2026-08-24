defmodule Ambry.Metadata.Providers.Audnexus do
  @moduledoc """
  Recording-level provider backed by Audnexus (audnex.us).

  Audnexus is an open-source, self-hostable aggregation layer over Audible's
  own endpoints — the source for author profiles (with images) and chapter
  data by ASIN. Wraps the existing `AmbryScraping.Audnexus` HTTP client.

  Note on chapters: provider chapter *timestamps*
  describe Audible's retail edition, not the local rip — they are a title
  source, never a timeline source. The offsets are still returned here;
  the import UI is responsible for honoring that principle.
  """

  @behaviour Ambry.Metadata.Provider

  alias Ambry.Metadata.Provider
  alias AmbryScraping.Audnexus

  @impl Provider
  def id, do: "audnexus"

  @impl Provider
  def display_name, do: "Audnexus"

  @impl Provider
  def level, do: :recording

  @impl Provider
  def capabilities, do: [:author_search, :author_details, :chapters]

  @impl Provider
  def config_fields, do: []

  @impl Provider
  def search_authors(query, _config) do
    with {:ok, authors} <- Audnexus.search_authors(query) do
      {:ok,
       authors
       |> Enum.map(fn author ->
         %Provider.Author{provider: id(), id: author.id, name: author.name}
       end)
       |> sort_by_name_similarity(query)}
    end
  end

  # Audnexus name search is fuzzy to the point of returning unrelated
  # people (and whole book titles as "names"); order by similarity to the
  # query so the right person is preselected.
  defp sort_by_name_similarity(authors, query) do
    query = query |> String.trim() |> String.downcase()

    Enum.sort_by(
      authors,
      &String.jaro_distance(String.downcase(&1.name || ""), query),
      :desc
    )
  end

  @impl Provider
  def author_details(asin, _config) do
    with {:ok, details} <- Audnexus.author_details(asin) do
      {:ok,
       %Provider.Author{
         provider: id(),
         id: details.id,
         name: details.name,
         description: details.description,
         image_url: details.image
       }}
    end
  end

  @impl Provider
  def chapters(asin, _config) do
    with {:ok, chapters} <- Audnexus.book_chapters(asin) do
      {:ok,
       %Provider.Chapters{
         provider: id(),
         asin: chapters.asin,
         chapters:
           Enum.map(chapters.chapters, fn chapter ->
             %Provider.Chapter{
               title: chapter.title,
               start_offset_ms: chapter.start_offset_ms,
               length_ms: chapter.length_ms
             }
           end)
       }}
    end
  end
end
