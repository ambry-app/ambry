defmodule Ambry.Metadata.Providers.Hardcover do
  @moduledoc """
  Work-level metadata provider backed by Hardcover's GraphQL API
  (hardcover.app) — an alternative/complement to rreading-glasses.

  Evaluated 2026-08-01: search results arrive fully hydrated in one request
  (title, description, contributions with roles, large covers with
  dimensions, featured series with decimal-capable positions); author
  profiles carry bios and large images (450–1000px, better than Goodreads'
  ~700px ceiling). Series listings include translations as separate books
  at the same positions — harmless for importing a single work's facts.

  Requires the operator's API token (free account). Tokens are JWTs that
  **expire after one year** — expiry is decoded locally from the token and
  surfaced as admin notices via `config_notices/1`. Hardcover describes the
  API as still in flux, so queries stay minimal and parsing defensive.
  """

  @behaviour Ambry.Metadata.Provider

  alias Ambry.Metadata.Provider
  alias Ambry.Metadata.Provider.ConfigField
  alias Ambry.Metadata.Providers.Hardcover.Client

  @token_url "https://hardcover.app/account/api"
  @expiry_warning_days 30

  @impl Provider
  def id, do: "hardcover"

  @impl Provider
  def display_name, do: "Hardcover"

  @impl Provider
  def level, do: :work

  @impl Provider
  def capabilities, do: [:book_search, :book_details, :author_search, :author_details]

  @impl Provider
  def config_fields do
    [
      %ConfigField{
        key: :api_token,
        label: "API token",
        type: :secret,
        default: nil,
        help:
          "Free token from #{@token_url}. Hardcover tokens expire after one year — " <>
            "a reminder appears here as expiry approaches."
      }
    ]
  end

  @impl Provider
  def available?(config), do: is_binary(config[:api_token]) and config[:api_token] != ""

  @impl Provider
  def config_notices(config) do
    if available?(config) do
      expiry_notice(token_expiry(config[:api_token]))
    else
      [{:warning, "No API token configured — get a free token at #{@token_url}."}]
    end
  end

  @search_books_query """
  query SearchBooks($query: String!) {
    search(query: $query, query_type: "book", per_page: 10) { results }
  }
  """

  @impl Provider
  def search_books(query, config) do
    with {:ok, data} <- Client.query(config, @search_books_query, %{query: query}) do
      hits = get_in(data, ["search", "results", "hits"]) || []
      {:ok, hits |> Enum.map(&search_hit_to_book/1) |> Enum.reject(&is_nil/1)}
    end
  end

  @book_details_query """
  query BookDetails($id: Int!) {
    books_by_pk(id: $id) {
      id
      title
      release_date
      description
      image { url }
      book_series { position details series { id name } }
      contributions { contribution author { id name } }
    }
  }
  """

  @impl Provider
  def book_details(book_id, config) do
    with {:ok, id} <- parse_id(book_id),
         {:ok, %{"books_by_pk" => book}} when is_map(book) <-
           Client.query(config, @book_details_query, %{id: id}) do
      {:ok,
       %Provider.Book{
         provider: id(),
         id: to_string(book["id"]),
         title: book["title"],
         description: presence(book["description"]),
         cover_url: get_in(book, ["image", "url"]),
         published: published_date(book["release_date"]),
         authors: contributions_to_authors(book["contributions"]),
         series: book_series(book["book_series"])
       }}
    else
      {:ok, _other} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  @search_authors_query """
  query SearchAuthors($query: String!) {
    search(query: $query, query_type: "author", per_page: 5) { results }
  }
  """

  @impl Provider
  def search_authors(query, config) do
    with {:ok, data} <- Client.query(config, @search_authors_query, %{query: query}) do
      hits = get_in(data, ["search", "results", "hits"]) || []

      authors =
        for %{"document" => doc} <- hits, doc["name"] do
          %Provider.Author{
            provider: id(),
            id: to_string(doc["id"]),
            name: doc["name"],
            image_url: get_in(doc, ["image", "url"])
          }
        end

      {:ok, sort_by_name_similarity(authors, query)}
    end
  end

  # like the other providers: fuzzy search returns unrelated people, so
  # order by similarity to the query for a sensible preselection
  defp sort_by_name_similarity(authors, query) do
    query = query |> String.trim() |> String.downcase()

    Enum.sort_by(
      authors,
      &String.jaro_distance(String.downcase(&1.name || ""), query),
      :desc
    )
  end

  @author_details_query """
  query AuthorDetails($id: Int!) {
    authors_by_pk(id: $id) {
      id
      name
      bio
      image { url }
    }
  }
  """

  @impl Provider
  def author_details(author_id, config) do
    with {:ok, id} <- parse_id(author_id),
         {:ok, %{"authors_by_pk" => author}} when is_map(author) <-
           Client.query(config, @author_details_query, %{id: id}) do
      {:ok,
       %Provider.Author{
         provider: id(),
         id: to_string(author["id"]),
         name: author["name"],
         description: presence(author["bio"]),
         image_url: get_in(author, ["image", "url"])
       }}
    else
      {:ok, _other} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Decodes the expiry from a Hardcover API token (a JWT with an `exp`
  claim) without verifying the signature — we only need the date.
  """
  def token_expiry(token) when is_binary(token) do
    with [_header, payload, _signature] <- String.split(token, "."),
         {:ok, json} <- Base.url_decode64(payload, padding: false),
         {:ok, %{"exp" => exp}} when is_integer(exp) <- Jason.decode(json),
         {:ok, datetime} <- DateTime.from_unix(exp) do
      {:ok, datetime}
    else
      _other -> :error
    end
  end

  defp expiry_notice({:ok, expiry}) do
    days_left = DateTime.diff(expiry, DateTime.utc_now(), :day)
    date = expiry |> DateTime.to_date() |> Date.to_string()

    cond do
      days_left < 0 ->
        [{:error, "API token expired on #{date} — regenerate it at #{@token_url}."}]

      days_left <= @expiry_warning_days ->
        [
          {:warning,
           "API token expires on #{date} (in #{days_left} days) — regenerate it at #{@token_url}."}
        ]

      true ->
        [{:info, "API token valid until #{date} (Hardcover tokens expire after one year)."}]
    end
  end

  defp expiry_notice(:error), do: []

  defp search_hit_to_book(%{"document" => doc}) when is_map(doc) do
    if doc["title"] do
      %Provider.Book{
        provider: id(),
        id: to_string(doc["id"]),
        title: doc["title"],
        description: presence(doc["description"]),
        cover_url: get_in(doc, ["image", "url"]),
        published: published_date(doc["release_date"]),
        authors: contributions_to_authors(doc["contributions"]),
        series: featured_series(doc["featured_series"])
      }
    end
  end

  defp search_hit_to_book(_hit), do: nil

  defp published_date(raw) do
    raw
    |> Provider.PublishedDate.from_string()
    |> Provider.PublishedDate.assume_jan1_is_year_only()
  end

  # a null contribution role means "Author"; anything else (Cover Artist,
  # Illustrator, Translator, …) is not an author credit
  defp contributions_to_authors(contributions) do
    for %{"author" => author} = contribution <- contributions || [],
        is_map(author),
        contribution["contribution"] in [nil, "Author"] do
      %Provider.Contributor{
        id: to_string(author["id"]),
        name: author["name"],
        role: "author"
      }
    end
  end

  defp featured_series(%{"series" => %{"id" => id, "name" => name}} = featured) do
    [
      %Provider.Series{
        id: to_string(id),
        name: name,
        number: presence(featured["details"]) || format_position(featured["position"])
      }
    ]
  end

  defp featured_series(_other), do: []

  defp book_series(book_series) do
    for %{"series" => %{"id" => id, "name" => name}} = entry <- book_series || [] do
      %Provider.Series{
        id: to_string(id),
        name: name,
        number: presence(entry["details"]) || format_position(entry["position"])
      }
    end
  end

  defp format_position(nil), do: nil

  defp format_position(position) when is_float(position) do
    if position == Float.round(position),
      do: position |> trunc() |> to_string(),
      else: to_string(position)
  end

  defp format_position(position), do: to_string(position)

  defp parse_id(id) do
    case Integer.parse(to_string(id)) do
      {int, ""} -> {:ok, int}
      _other -> {:error, :invalid_id}
    end
  end

  defp presence(nil), do: nil
  defp presence(""), do: nil
  defp presence(value), do: value
end
