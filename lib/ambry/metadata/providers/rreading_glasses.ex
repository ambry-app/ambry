defmodule Ambry.Metadata.Providers.RreadingGlasses do
  @moduledoc """
  Work-level metadata provider backed by a rreading-glasses server.

  rreading-glasses (github.com/blampe/rreading-glasses) serves
  Goodreads-quality work/edition/author/series data over a clean JSON API
  (originally the Readarr metadata contract). The default configuration
  points at the public instance (`api.bookinfo.pro`); operators can point
  the base URL at a self-hosted instance instead.

  API notes (verified against the public instance, 2026-08-01):

    * `GET /search?q=` returns skinny results (`bookId`/`workId`/author id)
      which are hydrated in one round-trip via `GET /book/bulk?id=…&id=…`
      (book ids, repeated params). The swagger spec's `GET /bulk` is stale —
      the real route is `/book/bulk`.
    * `GET /work/{id}` returns a work with its editions (`Books`), series
      (with per-work positions), and authors embedded.
    * `GET /author/{id}` is a large payload (hundreds of KB) but fine for
      interactive use; there is no author search endpoint, so author search
      goes through book search and hydrates the distinct author ids.
    * Edition ASINs are present on most editions — the bridge to
      recording-level providers.
  """

  @behaviour Ambry.Metadata.Provider

  alias Ambry.Metadata.Provider
  alias Ambry.Metadata.Provider.ConfigField
  alias Ambry.Metadata.Providers.RreadingGlasses.Client

  @max_author_hydrations 3

  @impl Provider
  def id, do: "rreading_glasses"

  @impl Provider
  def display_name, do: "rreading-glasses"

  @impl Provider
  def level, do: :work

  @impl Provider
  def capabilities, do: [:book_search, :book_details, :author_search, :author_details]

  @impl Provider
  def config_fields do
    [
      %ConfigField{
        key: :base_url,
        label: "Base URL",
        type: :string,
        default: "https://api.bookinfo.pro",
        help: "Public instance by default; point at a self-hosted rreading-glasses to switch."
      }
    ]
  end

  @impl Provider
  def search_books(query, config) do
    with {:ok, results} <- Client.get_json(base_url(config), "/search", q: query) do
      results
      |> Enum.map(& &1["bookId"])
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> hydrate_books(config)
    end
  end

  @impl Provider
  def book_details(work_id, config) do
    with {:ok, work} <- Client.get_json(base_url(config), "/work/#{work_id}", []) do
      {:ok, work_to_book(work)}
    end
  end

  @impl Provider
  def search_authors(query, config) do
    with {:ok, results} <- Client.get_json(base_url(config), "/search", q: query) do
      authors =
        results
        |> Enum.map(&get_in(&1, ["author", "id"]))
        |> Enum.reject(&is_nil/1)
        |> Enum.uniq()
        |> Enum.take(@max_author_hydrations)
        |> Enum.flat_map(fn author_id ->
          case author_details(author_id, config) do
            {:ok, author} -> [author]
            {:error, _reason} -> []
          end
        end)

      {:ok, authors}
    end
  end

  @impl Provider
  def author_details(author_id, config) do
    with {:ok, author} <- Client.get_json(base_url(config), "/author/#{author_id}", []) do
      {:ok,
       %Provider.Author{
         provider: id(),
         id: to_string(author["ForeignId"]),
         name: author["Name"],
         description: presence(author["Description"]),
         image_url: presence(author["ImageUrl"])
       }}
    end
  end

  defp base_url(config), do: config[:base_url] || "https://api.bookinfo.pro"

  defp hydrate_books([], _config), do: {:ok, []}

  defp hydrate_books(book_ids, config) do
    params = Enum.map(book_ids, &{:id, &1})

    case Client.get_json(base_url(config), "/book/bulk", params) do
      {:ok, %{"Works" => works}} ->
        by_edition_id =
          for work <- works, edition <- work["Books"] || [], into: %{} do
            {edition["ForeignId"], work}
          end

        books =
          book_ids
          |> Enum.map(fn book_id ->
            case by_edition_id[book_id] do
              nil -> nil
              work -> work_to_book(work, book_id)
            end
          end)
          |> Enum.reject(&is_nil/1)
          |> Enum.uniq_by(& &1.id)

        {:ok, books}

      {:ok, _other} ->
        {:error, :unexpected_response_payload}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp work_to_book(work, preferred_edition_id \\ nil) do
    editions = work["Books"] || []
    best = best_edition(editions, preferred_edition_id, work["BestBookId"])

    %Provider.Book{
      provider: id(),
      id: to_string(work["ForeignId"]),
      title: work["Title"],
      description: best["Description"] || first_present(editions, "Description"),
      cover_url: best["ImageUrl"] || first_present(editions, "ImageUrl"),
      published:
        Provider.PublishedDate.from_string(work["ReleaseDateRaw"] || best["ReleaseDateRaw"]),
      publisher: presence(best["Publisher"]),
      language: presence(best["Language"]),
      format: presence(best["Format"]),
      asin: presence(best["Asin"]),
      authors: authors(work),
      series: series(work),
      editions: Enum.map(editions, &edition/1)
    }
  end

  defp best_edition(editions, preferred_edition_id, best_book_id) do
    Enum.find(editions, &(&1["ForeignId"] == preferred_edition_id)) ||
      Enum.find(editions, &(&1["ForeignId"] == best_book_id)) ||
      Enum.find(editions, &presence(&1["ImageUrl"])) ||
      List.first(editions) ||
      %{}
  end

  defp first_present(editions, field) do
    Enum.find_value(editions, &presence(&1[field]))
  end

  defp authors(work) do
    for author <- work["Authors"] || [] do
      %Provider.Contributor{
        id: to_string(author["ForeignId"]),
        name: author["Name"],
        role: "author"
      }
    end
  end

  defp series(work) do
    work_id = work["ForeignId"]

    for series <- work["Series"] || [],
        link <- series["LinkItems"] || [],
        link["ForeignWorkId"] == work_id do
      %Provider.Series{
        id: to_string(series["ForeignId"]),
        name: series["Title"],
        number: presence(link["PositionInSeries"])
      }
    end
  end

  defp edition(edition) do
    %Provider.Edition{
      id: to_string(edition["ForeignId"]),
      title: edition["Title"],
      asin: presence(edition["Asin"]),
      description: presence(edition["Description"]),
      language: presence(edition["Language"]),
      format: presence(edition["Format"]),
      publisher: presence(edition["Publisher"]),
      published: Provider.PublishedDate.from_string(edition["ReleaseDateRaw"]),
      cover_url: presence(edition["ImageUrl"])
    }
  end

  defp presence(nil), do: nil
  defp presence(""), do: nil
  defp presence(value), do: value
end
