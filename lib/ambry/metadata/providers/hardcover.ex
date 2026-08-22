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
  def capabilities,
    do: [:book_search, :book_details, :author_search, :author_details, :editions, :editions_bulk]

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
    # Free text only — the search endpoint takes one string, so a structured
    # query flattens to its rendering and loses nothing.
    with {:ok, data} <-
           Client.query(config, @search_books_query, %{query: to_string(query)}) do
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

  # Hardcover's `contribution` is free text and the narrator credit is written
  # at least five ways. Measured across 400 audiobook editions: "Narrator" 286,
  # "Reading" 9, "Reader" 7, "narrator" 7, "Read by" 5. Matching the one
  # spelling dropped a tenth of all narrator credits, and on The Martian it
  # dropped R.C. Bray's recording — the delisted one this whole capability
  # exists to recover — while keeping every Wil Wheaton record.
  @narrator_roles ["narrator", "reader", "reading", "read by"]

  # The same set in the casings seen upstream: the server's `_in` is
  # case-sensitive, and `_ilike`/`_iregex` are refused outright (403 "ilike and
  # related operations are not permitted on this server"). Recall only — the
  # authoritative, case-insensitive test is `narrator_role?/1` below.
  @narrator_roles_upstream [
    "Narrator",
    "narrator",
    "Reader",
    "reader",
    "Reading",
    "reading",
    "Read by",
    "read by"
  ]

  @audiobook_format 2

  # The audio filter belongs in the WHERE clause, not in Elixir. Fetching an
  # arbitrary unordered page and filtering it here silently capped coverage at
  # whichever editions the server happened to return first: The Martian has
  # **150** editions, so `limit: 60` decided by nothing at all which ones we
  # got, and the audiobooks were not among them. Filtering upstream, the same
  # book yields 13 rows — the entire audio set, comfortably inside the limit.
  @editions_query """
  query AudioEditions($id: Int!, $roles: [String!]) {
    editions(
      where: {
        book_id: {_eq: $id},
        _or: [
          {reading_format_id: {_eq: #{@audiobook_format}}},
          {audio_seconds: {_is_null: false}},
          {contributions: {contribution: {_in: $roles}}}
        ]
      },
      limit: 60
    ) {
      id
      title
      release_date
      asin
      audio_seconds
      reading_format_id
      publisher { name }
      image { url }
      contributions { contribution author { id name } }
      book { description contributions { contribution author { id name } } }
    }
  }
  """

  # The same filter as `@editions_query`, over several books at once. Hasura
  # takes `_in` on `book_id`, so asking about seven works costs one request
  # rather than seven -- which is what makes it possible to open *every*
  # candidate work instead of guessing which few are worth opening.
  #
  # The limit is across all of them, so it is generous and its exhaustion is
  # reported rather than silently truncating.
  @editions_bulk_query """
  query AudioEditionsBulk($ids: [Int!], $roles: [String!]) {
    editions(
      where: {
        book_id: {_in: $ids},
        _or: [
          {reading_format_id: {_eq: #{@audiobook_format}}},
          {audio_seconds: {_is_null: false}},
          {contributions: {contribution: {_in: $roles}}}
        ]
      },
      limit: 500
    ) {
      id
      book_id
      title
      release_date
      asin
      audio_seconds
      reading_format_id
      publisher { name }
      image { url }
      contributions { contribution author { id name } }
      book { description contributions { contribution author { id name } } }
    }
  }
  """

  @doc """
  The audiobook editions of several works, keyed by work id.
  """
  @impl Provider
  def editions_bulk(work_ids, config) do
    ids =
      Enum.flat_map(work_ids, fn id ->
        case parse_id(id) do
          {:ok, parsed} -> [parsed]
          _error -> []
        end
      end)

    with false <- ids == [],
         {:ok, %{"editions" => editions}} <-
           Client.query(config, @editions_bulk_query, %{
             ids: ids,
             roles: @narrator_roles_upstream
           }) do
      {:ok,
       editions
       |> Enum.filter(&audio_edition?/1)
       |> Enum.group_by(&to_string(&1["book_id"]), &edition_to_book/1)}
    else
      true -> {:ok, %{}}
      {:ok, _other} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  The audiobook editions of a work.

  This is the answer to recordings a storefront has delisted. Audible's
  catalog API is a storefront, not a bibliography: when a publisher loses the
  rights and the title is pulled, it disappears from search *and* from direct
  ASIN lookup, leaving no trace that the recording ever existed. Hardcover
  keeps the edition, its narrator and its cover.
  """
  @impl Provider
  def editions(work_id, config) do
    with {:ok, id} <- parse_id(work_id),
         {:ok, %{"editions" => editions}} <-
           Client.query(config, @editions_query, %{id: id, roles: @narrator_roles_upstream}) do
      {:ok, editions |> Enum.filter(&audio_edition?/1) |> Enum.map(&edition_to_book/1)}
    else
      {:ok, _other} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  # `reading_format_id` is unreliable as a *negative* — several Neuromancer
  # editions with explicit Narrator credits and audio publishers are stored as
  # format 1 ("Read"), which is why it can't be the filter. As a positive it is
  # perfectly good evidence, so it joins the other two tells rather than
  # replacing them: a narrator credit under any of its spellings, a runtime, or
  # the format saying audiobook.
  defp audio_edition?(edition) do
    narrators(edition) != [] or not is_nil(edition["audio_seconds"]) or
      edition["reading_format_id"] == @audiobook_format
  end

  defp narrators(edition) do
    edition["contributions"]
    |> List.wrap()
    |> Enum.filter(&narrator_role?(&1["contribution"]))
    |> Enum.map(& &1["author"])
    |> Enum.reject(&is_nil/1)
  end

  # A nil contribution is NOT admitted, tempting as it is: nil is also how
  # Hardcover credits the author (Andy Weir is nil on every Martian edition),
  # so reading it as a narrator would credit authors as their own readers.
  defp narrator_role?(role) when is_binary(role), do: String.downcase(role) in @narrator_roles
  defp narrator_role?(_role), do: false

  defp edition_to_book(edition) do
    %Provider.Book{
      provider: id(),
      id: to_string(edition["id"]),
      asin: presence(edition["asin"]),
      title: edition["title"],
      # Already fetched and already used to decide this is an audio edition
      # at all; keeping it costs nothing and it is the one fact that
      # distinguishes two recordings of the same book.
      duration_seconds: edition["audio_seconds"],
      # From the WORK's contributions, not the edition's own. An edition of a
      # book has that book's author by definition, and reading the edition's
      # list instead promotes whoever upstream filed under the nil role —
      # which on The Martian's B082BHWQCJ is Wil Wheaton, its *narrator*. That
      # record then arrived crediting Wheaton as an author of the novel, and
      # was pre-ticked for it, because naming a superset of the right authors
      # reads as corroboration. The work's own list can't be wrong that way.
      #
      # Editions need an author at all because a record naming none used to be
      # scored as naming the WRONG one — a flat quarter off, enough on The
      # Martian for Audible's Wheaton edition to outrank the recording
      # actually in hand.
      authors: contributions_to_authors(get_in(edition, ["book", "contributions"])),
      # The book's blurb, for the same reason and by the same hop. `editions`
      # has no description field at all — not omitted from this query, absent
      # from the type — so without this an edition record can carry none, and
      # the only description a recording could be given came from the
      # storefront. A storefront describes the reading it is *selling*:
      # Audible's Martian copy is about Wil Wheaton, which is the wrong
      # description for R.C. Bray's recording of that book.
      #
      # It is the work's text on a recording's record, deliberately. Every
      # edition of the book carries the same words, and both consumers group
      # candidates by value — `Evidence.group/1` and `Seed.scalar/2`'s
      # `collapse` — so thirteen editions offer one chip, not thirteen.
      description: presence(get_in(edition, ["book", "description"])),
      cover_url: get_in(edition, ["image", "url"]),
      publisher: get_in(edition, ["publisher", "name"]),
      # Old editions frequently carry the *work's* date rather than their own
      # (four Neuromancer editions all claim 1984-07-01), so this is offered
      # as a proposal like any other and is not to be trusted over a
      # storefront's date when one exists.
      published: published_date(edition["release_date"]),
      narrators:
        Enum.map(narrators(edition), fn narrator ->
          %Provider.Contributor{
            id: to_string(narrator["id"]),
            name: narrator["name"],
            role: "narrator"
          }
        end)
    }
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
