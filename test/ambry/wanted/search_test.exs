defmodule Ambry.Wanted.SearchTest do
  @moduledoc """
  The two provider levels are differently blind about the future, so both are
  asked and neither is preferred. These are the cases that made that the
  design rather than a preference.
  """

  use Ambry.DataCase, async: false
  use Patch

  alias Ambry.Metadata.Provider
  alias Ambry.Metadata.ProviderConfig
  alias Ambry.Repo
  alias Ambry.Wanted.Search

  # Hardcover is filtered off the registry as unavailable until it has a
  # token, so patching its module alone would never be reached.
  setup do
    Repo.insert!(%ProviderConfig{
      provider_id: "hardcover",
      enabled: true,
      config: %{"api_token" => "test-token"}
    })

    :ok
  end

  defp product(id, title, opts) do
    %Provider.Book{
      provider: "audible",
      id: id,
      title: title,
      asin: Keyword.get(opts, :asin),
      narrators: Keyword.get(opts, :narrators, []),
      duration_seconds: Keyword.get(opts, :duration_seconds),
      published: %Provider.PublishedDate{
        date: Keyword.get(opts, :date, ~D[2026-09-29]),
        display_format: :full
      }
    }
  end

  # A storefront lists what it is selling, so it has the preorder; a
  # bibliography lists what has been published, and there is no audiobook yet
  # to catalogue. This is the real shape of The Velvet Knife.
  test "a preorder only a storefront knows about is still offered" do
    patch(Ambry.Metadata.Providers.Audible, :search_books, fn _query, _config ->
      {:ok,
       [
         product("B0FKVNLXQS", "The Velvet Knife",
           narrators: [%{name: "Emily Ellet"}],
           duration_seconds: 36_000
         )
       ]}
    end)

    patch(Ambry.Metadata.Providers.Hardcover, :search_books, fn _query, _config -> {:ok, []} end)

    {candidates, _outcomes, _notes} =
      Search.candidates(%Provider.Query{title: "The Velvet Knife"})

    assert [candidate] = Enum.filter(candidates, &(&1.provider == "audible"))
    assert candidate.provider_id == "B0FKVNLXQS"
    assert candidate.published == ~D[2026-09-29]
    assert candidate.edition.narrators == ["Emily Ellet"]
    # An audiobook's runtime rides with it: it is what tells two recordings
    # of one book apart when everything else agrees.
    assert candidate.edition.duration_seconds == 36_000
  end

  test "the same recording from two providers is offered twice, not merged" do
    patch(Ambry.Metadata.Providers.Audible, :search_books, fn _query, _config ->
      {:ok, [product("B0GPDBGTTL", "Blightfall", date: ~D[2026-09-01])]}
    end)

    patch(Ambry.Metadata.Providers.Hardcover, :search_books, fn _query, _config ->
      {:ok, [%Provider.Book{provider: "hardcover", id: "2235778", title: "Blightfall"}]}
    end)

    patch(Ambry.Metadata.Providers.Hardcover, :editions, fn "2235778", _config ->
      {:ok,
       [
         %Provider.Book{
           provider: "hardcover",
           id: "33170376",
           title: "Blightfall",
           published: %Provider.PublishedDate{date: ~D[2026-09-01], display_format: :full}
         }
       ]}
    end)

    {candidates, _outcomes, _notes} = Search.candidates(%Provider.Query{title: "Blightfall"})

    assert candidates |> Enum.map(& &1.provider) |> Enum.sort() == ["audible", "hardcover"]
    assert candidates |> Enum.map(& &1.provider_id) |> Enum.sort() == ["33170376", "B0GPDBGTTL"]
  end

  test "a work-level provider is expanded into its audio editions" do
    patch(Ambry.Metadata.Providers.Audible, :search_books, fn _query, _config -> {:ok, []} end)

    patch(Ambry.Metadata.Providers.Hardcover, :search_books, fn _query, _config ->
      {:ok, [%Provider.Book{provider: "hardcover", id: "313448", title: "Neuromancer"}]}
    end)

    patch(Ambry.Metadata.Providers.Hardcover, :editions, fn "313448", _config ->
      {:ok,
       [
         %Provider.Book{
           provider: "hardcover",
           id: "e1",
           title: "Neuromancer",
           publisher: "Books on Tape",
           narrators: [%{name: "Robertson Dean"}],
           duration_seconds: 37_920,
           published: %Provider.PublishedDate{date: ~D[1984-07-01], display_format: :full}
         }
       ]}
    end)

    {candidates, _outcomes, _notes} = Search.candidates(%Provider.Query{title: "Neuromancer"})

    assert [edition] = Enum.filter(candidates, &(&1.provider == "hardcover"))
    assert edition.edition.publisher == "Books on Tape"
    assert edition.edition.duration_seconds == 37_920
    assert edition.published == ~D[1984-07-01]
    assert edition.work_title == "Neuromancer"
  end

  # A provider that can find the book but not list its recordings has nothing
  # to offer a watch, and saying so beats a silent absence.
  test "says when a provider could not contribute rather than staying quiet" do
    patch(Ambry.Metadata.Providers.Audible, :search_books, fn _query, _config -> {:ok, []} end)
    patch(Ambry.Metadata.Providers.Hardcover, :search_books, fn _query, _config -> {:ok, []} end)

    patch(Ambry.Metadata.Providers.RreadingGlasses, :search_books, fn _query, _config ->
      {:ok, [%Provider.Book{provider: "rreading_glasses", id: "w1", title: "A Book"}]}
    end)

    {_candidates, _outcomes, notes} = Search.candidates(%Provider.Query{title: "A Book"})

    assert Enum.any?(notes, &(&1 =~ "audio editions"))
  end

  @tag :capture_log
  test "a failed provider is reported, not mistaken for having nothing" do
    patch(Ambry.Metadata.Providers.Audible, :search_books, fn _query, _config ->
      {:error, :timeout}
    end)

    patch(Ambry.Metadata.Providers.Hardcover, :search_books, fn _query, _config -> {:ok, []} end)

    {_candidates, outcomes, _notes} = Search.candidates(%Provider.Query{title: "Anything"})

    assert Enum.any?(outcomes, &(&1["id"] == "audible" and &1["status"] == "failed"))
  end
end
