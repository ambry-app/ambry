defmodule Ambry.Inbox.AutoMatch do
  @moduledoc """
  Proposes what an inbox item is, so confirming it can be one click.

  ## Two matches, not one

  An item needs a **work** match (which Book — title, authors, series) and a
  **recording** match (which Media — narrators, cover, chapters, release
  date). They use different keys and fail independently: an ASIN identifies a
  recording outright, title-and-author identifies a work fuzzily, and you can
  land the right work with the wrong recording — a dramatized adaptation
  instead of the standard narration — or the right recording under the wrong
  work. So each gets its own ranked candidates and its own score.

  Nothing is applied. This writes proposals onto the inbox item; the operator
  approves, and approval is what creates records.

  ## Why the whole ranked list is kept

  Storing only the winner would make "what else did it find?" a fresh round
  of provider calls every time the operator looked. The full list, with each
  candidate's score and the query that produced it, makes reviewing
  alternatives instant — and leaves re-searching for the case it's actually
  for, where the right answer isn't in the list at all.

  ## Local records outrank providers

  A work already in the library is the best possible match: it's what stops a
  second recording of a book from creating a duplicate Book. So local hits
  are ranked ahead of provider results at equal confidence.
  """

  alias Ambry.Books
  alias Ambry.Inbox.InboxItem
  alias Ambry.Inbox.ReleaseName
  alias Ambry.Metadata.Providers
  alias Ambry.Metadata.Registry

  require Logger

  @candidate_limit 8

  @doc """
  Builds work and recording proposals for an item.

  Returns the attrs to store; never raises, and degrades to whatever it could
  find — a provider being down means fewer candidates, not a failed item.
  """
  def match(%InboxItem{} = item) do
    hints = hints(item)

    %{
      matches: %{
        "work" => match_work(hints),
        "recording" => match_recording(hints),
        "hints" => stringify_hints(hints)
      }
    }
  end

  @doc """
  What we think the item is, from its tags first and its release name second.

  Tags win because they're vastly more reliable — measured across a real
  library, 96% of releases carry a title and author in tags, against 55%
  whose *name* yields an author.
  """
  def hints(%InboxItem{} = item) do
    tags = item.tags || %{}
    parsed = ReleaseName.parse(item.path)

    %{
      title: presence(tags["book_title"]) || parsed.title,
      author: first(tags["authors"]) || parsed.author,
      narrator: first(tags["narrators"]) || parsed.narrator,
      series: presence(tags["series"]) || parsed.series,
      asin: presence(tags["asin"]) || parsed.asin
    }
  end

  defp match_work(hints) do
    query = query_for(hints)

    level_result(query, local_books(query, hints) ++ provider_books(:work, query, hints))
  end

  # An ASIN is a recording-level key, so when there is one it *is* the query:
  # a hit on it is definitive in a way no title match ever is.
  defp match_recording(%{asin: asin} = hints) when is_binary(asin) do
    level_result(asin, provider_books(:recording, asin, hints))
  end

  defp match_recording(hints) do
    query = query_for(hints)

    level_result(query, provider_books(:recording, query, hints))
  end

  defp level_result(query, candidates) do
    candidates = candidates |> Enum.sort_by(& &1["score"], :desc) |> Enum.take(@candidate_limit)

    %{
      "query" => query,
      "candidates" => candidates,
      # the operator confirms; this is only the suggestion
      "selected" => candidates |> List.first() |> selected_ref(),
      "confidence" => confidence(candidates)
    }
  end

  defp selected_ref(nil), do: nil
  defp selected_ref(candidate), do: %{"source" => candidate["source"], "id" => candidate["id"]}

  # Confidence is about the *decision*, not just the top hit: a strong match
  # with an equally strong runner-up is exactly the case a human should look
  # at, so a close second pulls it down.
  defp confidence([]), do: 0.0

  defp confidence([best]), do: best["score"]

  defp confidence([best, second | _rest]) do
    penalty = 0.5 * second["score"] / max(best["score"], 0.001)

    (best["score"] * (1.0 - penalty))
    |> max(0.0)
    |> min(best["score"])
    |> Float.round(3)
  end

  defp local_books(nil, _hints), do: []

  defp local_books(query, hints) do
    {books, _more} = Books.list_books(0, @candidate_limit, %{search: query})

    Enum.map(books, fn book ->
      %{
        "source" => "local",
        "id" => book.id,
        "title" => book.title,
        "authors" => Enum.map(book.authors || [], & &1.name),
        "series" => Enum.map(book.series || [], & &1.name),
        "published" => book.published && Date.to_iso8601(book.published),
        # a work already in the library beats an equally-good provider hit:
        # reusing it is what prevents duplicate Books
        "score" => score(book.title, Enum.map(book.authors || [], & &1.name), nil, hints) + 0.05
      }
    end)
  end

  defp provider_books(_level, nil, _hints), do: []

  defp provider_books(level, query, hints) do
    [level: level, capability: :book_search]
    |> Registry.enabled()
    |> Enum.flat_map(&search_provider(&1, query, hints))
  end

  # Providers are tried in the operator's priority order, and one being down,
  # rate-limited or slow costs its results only.
  defp search_provider(entry, query, hints) do
    case Providers.search_books(entry.id, query, []) do
      {:ok, books} ->
        books |> Enum.take(@candidate_limit) |> Enum.map(&provider_candidate(&1, entry, hints))

      {:error, reason} ->
        Logger.warning(fn ->
          "Auto-match: #{entry.id} failed for #{inspect(query)}: #{inspect(reason)}"
        end)

        []
    end
  end

  defp provider_candidate(book, entry, hints) do
    authors = Enum.map(book.authors || [], & &1.name)
    narrators = Enum.map(book.narrators || [], & &1.name)

    %{
      "source" => "provider:#{entry.id}",
      "provider_name" => entry.display_name,
      "id" => book.id,
      "asin" => book.asin,
      "title" => book.title,
      "authors" => authors,
      "narrators" => narrators,
      "series" => Enum.map(book.series || [], & &1.name),
      "published" =>
        book.published && book.published.date && Date.to_iso8601(book.published.date),
      "publisher" => book.publisher,
      "cover_url" => book.cover_url,
      "description" => book.description,
      "score" => score(book.title, authors, book.asin, hints)
    }
  end

  # An ASIN match is identity, not similarity — nothing else can earn 1.0.
  defp score(_title, _authors, asin, %{asin: asin}) when is_binary(asin), do: 1.0

  defp score(title, authors, _asin, hints) do
    title_score = similarity(title, hints.title)

    case author_similarity(authors, hints.author) do
      nil -> Float.round(title_score, 3)
      author_score -> Float.round(title_score * 0.75 + author_score * 0.25, 3)
    end
  end

  defp author_similarity(_authors, nil), do: nil
  defp author_similarity([], _author), do: 0.0

  defp author_similarity(authors, author) do
    authors |> Enum.map(&similarity(&1, author)) |> Enum.max(fn -> 0.0 end)
  end

  defp similarity(nil, _other), do: 0.0
  defp similarity(_string, nil), do: 0.0

  defp similarity(string, other) do
    String.jaro_distance(normalize(string), normalize(other))
  end

  # Titles differ in punctuation and subtitle noise far more often than in
  # substance, and none of that should cost a match.
  defp normalize(string) do
    string
    |> String.downcase()
    |> String.replace(~r/\b(unabridged|abridged|a novel|audiobook)\b/, " ")
    |> String.replace(~r/[^\p{L}\p{N}\s]/u, " ")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp query_for(%{title: nil}), do: nil
  defp query_for(%{title: title, author: nil}), do: title
  defp query_for(%{title: title, author: author}), do: "#{title} #{author}"

  defp stringify_hints(hints) do
    Map.new(hints, fn {key, value} -> {to_string(key), value} end)
  end

  defp first(nil), do: nil
  defp first([]), do: nil
  defp first([value | _rest]), do: presence(value)
  defp first(value), do: presence(value)

  defp presence(nil), do: nil
  defp presence(string) when is_binary(string), do: with("" <- String.trim(string), do: nil)
  defp presence(_other), do: nil
end
