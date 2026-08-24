defmodule Ambry.Wanted.SearchTest do
  @moduledoc """
  Providers are selected by capability and their answers are filtered to what
  has not come out yet. These are the cases that made both of those the
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
    date = if Keyword.has_key?(opts, :date), do: Keyword.get(opts, :date), else: ~D[2099-09-29]

    %Provider.Book{
      provider: "audible",
      id: id,
      title: title,
      asin: Keyword.get(opts, :asin),
      narrators: Keyword.get(opts, :narrators, []),
      duration_seconds: Keyword.get(opts, :duration_seconds),
      published: date && %Provider.PublishedDate{date: date, display_format: :full}
    }
  end

  defp no_hardcover_results do
    patch(Ambry.Metadata.Providers.Hardcover, :search_books, fn _query, _config -> {:ok, []} end)
  end

  # A catalogue of what is for sale carries preorders; a catalogue of what has
  # been published has no entry for a recording that has not come out. This is
  # the real shape of The Velvet Knife, and why every capable provider is
  # asked rather than one being chosen.
  test "a preorder only one provider knows about is still offered" do
    patch(Ambry.Metadata.Providers.Audible, :search_books, fn _query, _config ->
      {:ok,
       [
         product("B0FKVNLXQS", "The Velvet Knife",
           narrators: [%{name: "Emily Ellet"}],
           duration_seconds: 36_000
         )
       ]}
    end)

    no_hardcover_results()

    {candidates, _outcomes, _notes} =
      Search.candidates(%Provider.Query{title: "The Velvet Knife"})

    assert [candidate] = Enum.filter(candidates, &(&1.provider == "audible"))
    assert candidate.provider_id == "B0FKVNLXQS"
    assert candidate.published == ~D[2099-09-29]
    assert candidate.edition.narrators == ["Emily Ellet"]
    # An audiobook's runtime rides with it: it is what tells two recordings
    # of one book apart when everything else agrees.
    assert candidate.edition.duration_seconds == 36_000
  end

  test "the same recording from two providers is offered twice, not merged" do
    patch(Ambry.Metadata.Providers.Audible, :search_books, fn _query, _config ->
      {:ok, [product("B0GPDBGTTL", "Blightfall", date: ~D[2099-09-01])]}
    end)

    patch(Ambry.Metadata.Providers.Hardcover, :search_books, fn _query, _config ->
      {:ok, [%Provider.Book{provider: "hardcover", id: "2235778", title: "Blightfall"}]}
    end)

    patch(Ambry.Metadata.Providers.Hardcover, :editions_bulk, fn ["2235778"], _config ->
      {:ok,
       %{
         "2235778" => [
           %Provider.Book{
             provider: "hardcover",
             id: "33170376",
             title: "Blightfall",
             published: %Provider.PublishedDate{date: ~D[2099-09-01], display_format: :full}
           }
         ]
       }}
    end)

    {candidates, _outcomes, _notes} = Search.candidates(%Provider.Query{title: "Blightfall"})

    assert candidates |> Enum.map(& &1.provider) |> Enum.sort() == ["audible", "hardcover"]
    assert candidates |> Enum.map(& &1.provider_id) |> Enum.sort() == ["33170376", "B0GPDBGTTL"]
  end

  # A work is not a recording, so a work-level answer has to be opened before
  # it can offer anything. That is a difference in shape, not in standing.
  test "a provider that answers with works is expanded into its audio editions" do
    patch(Ambry.Metadata.Providers.Audible, :search_books, fn _query, _config -> {:ok, []} end)

    patch(Ambry.Metadata.Providers.Hardcover, :search_books, fn _query, _config ->
      {:ok, [%Provider.Book{provider: "hardcover", id: "2235778", title: "Blightfall"}]}
    end)

    patch(Ambry.Metadata.Providers.Hardcover, :editions_bulk, fn ["2235778"], _config ->
      {:ok,
       %{
         "2235778" => [
           %Provider.Book{
             provider: "hardcover",
             id: "33170376",
             title: "Blightfall",
             publisher: "Listening Library",
             narrators: [%{name: "Eddie Lopez"}],
             duration_seconds: 45_660,
             published: %Provider.PublishedDate{date: ~D[2099-09-01], display_format: :full}
           }
         ]
       }}
    end)

    {candidates, _outcomes, _notes} = Search.candidates(%Provider.Query{title: "Blightfall"})

    assert [edition] = Enum.filter(candidates, &(&1.provider == "hardcover"))
    assert edition.edition.publisher == "Listening Library"
    assert edition.edition.duration_seconds == 45_660
    assert edition.work_title == "Blightfall"
  end

  # A work-level provider ranks by its own idea of relevance, and the right
  # book can sit well down that list -- Neuromancer by William Gibson puts the
  # actual novel sixth. Opening only the promising ones guesses at exactly the
  # thing that is uncertain.
  test "every matched work is opened, not just the first few" do
    patch(Ambry.Metadata.Providers.Audible, :search_books, fn _query, _config -> {:ok, []} end)

    works =
      for n <- 1..7 do
        %Provider.Book{provider: "hardcover", id: "w#{n}", title: "Work #{n}"}
      end

    patch(Ambry.Metadata.Providers.Hardcover, :search_books, fn _q, _c -> {:ok, works} end)

    patch(Ambry.Metadata.Providers.Hardcover, :editions_bulk, fn ids, _config ->
      # The one worth having is last, exactly where a guess would miss it.
      assert length(ids) == 7

      {:ok,
       %{
         "w7" => [
           %Provider.Book{
             provider: "hardcover",
             id: "buried",
             title: "The One",
             published: %Provider.PublishedDate{date: ~D[2099-01-01], display_format: :full}
           }
         ]
       }}
    end)

    {candidates, _outcomes, notes} = Search.candidates(%Provider.Query{title: "Work"})

    assert Enum.map(candidates, & &1.provider_id) == ["buried"]
    # Nothing was left unopened, so nothing is reported as cut.
    refute Enum.any?(notes, &(&1 =~ "unopened"))
  end

  describe "only what has not come out yet" do
    # Neuromancer is the case this exists for: a dozen real audio editions,
    # every one of them decades old. A watch is a reminder about something
    # still to come, so none of them is one.
    test "recordings that are already published are not offered" do
      patch(Ambry.Metadata.Providers.Audible, :search_books, fn _query, _config ->
        {:ok,
         [
           product("old", "Neuromancer", date: ~D[1984-07-01]),
           product("coming", "Neuromancer", date: ~D[2099-01-01])
         ]}
      end)

      no_hardcover_results()

      {candidates, _outcomes, _notes} = Search.candidates(%Provider.Query{title: "Neuromancer"})

      assert Enum.map(candidates, & &1.provider_id) == ["coming"]
    end

    # "Nothing found" and "they are all already out" mean opposite things to
    # someone deciding whether a provider has the book at all.
    test "says how many were set aside rather than looking like nothing was found" do
      patch(Ambry.Metadata.Providers.Audible, :search_books, fn _query, _config ->
        {:ok,
         [
           product("a", "Neuromancer", date: ~D[1984-07-01]),
           product("b", "Neuromancer", date: ~D[2011-06-30])
         ]}
      end)

      no_hardcover_results()

      {candidates, _outcomes, notes} = Search.candidates(%Provider.Query{title: "Neuromancer"})

      assert candidates == []
      assert notes == ["2 already released not shown."]
    end

    test "an undated record is not evidence of the future either" do
      patch(Ambry.Metadata.Providers.Audible, :search_books, fn _query, _config ->
        {:ok, [product("undated", "Someday", date: nil)]}
      end)

      no_hardcover_results()

      {candidates, _outcomes, notes} = Search.candidates(%Provider.Query{title: "Someday"})

      assert candidates == []
      assert notes == ["1 with no date not shown."]
    end

    test "today is not the future; something out this morning is already out" do
      patch(Ambry.Metadata.Providers.Audible, :search_books, fn _query, _config ->
        {:ok,
         [
           product("today", "Out Now", date: ~D[2026-08-22]),
           product("tomorrow", "Out Soon", date: ~D[2026-08-23])
         ]}
      end)

      no_hardcover_results()

      {candidates, _outcomes, _notes} =
        Search.candidates(%Provider.Query{title: "Out"}, today: ~D[2026-08-22])

      assert Enum.map(candidates, & &1.provider_id) == ["tomorrow"]
    end
  end

  # Finding the book is not finding an audiobook. A work-level provider that
  # cannot then say which recordings the work has is not asked at all, rather
  # than asked and then apologised for.
  test "a provider that cannot list a work's recordings is never asked" do
    patch(Ambry.Metadata.Providers.Audible, :search_books, fn _query, _config -> {:ok, []} end)
    no_hardcover_results()

    patch(Ambry.Metadata.Providers.RreadingGlasses, :search_books, fn _query, _config ->
      {:ok, [%Provider.Book{provider: "rreading_glasses", id: "w1", title: "A Book"}]}
    end)

    {_candidates, outcomes, notes} = Search.candidates(%Provider.Query{title: "A Book"})

    refute_called(Ambry.Metadata.Providers.RreadingGlasses.search_books(_, _))
    refute Enum.any?(outcomes, &(&1["id"] =~ "rreading_glasses"))
    assert notes == []
  end

  @tag :capture_log
  test "a failed provider is reported, not mistaken for having nothing" do
    patch(Ambry.Metadata.Providers.Audible, :search_books, fn _query, _config ->
      {:error, :timeout}
    end)

    no_hardcover_results()

    {_candidates, outcomes, _notes} = Search.candidates(%Provider.Query{title: "Anything"})

    assert Enum.any?(outcomes, &(&1["id"] == "audible" and &1["status"] == "failed"))
  end
end
