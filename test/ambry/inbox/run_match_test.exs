defmodule Ambry.Inbox.RunMatchTest do
  use Ambry.DataCase
  use Patch

  alias Ambry.Inbox
  alias Ambry.Inbox.InboxItem
  alias Ambry.Inbox.RunMatch
  alias Ambry.Metadata.Providers

  setup do
    patch(Providers, :editions, fn _id, _work_id, _opts -> {:ok, []} end)
    patch(Providers, :book_details, fn _id, _book_id, _opts -> {:error, :not_stubbed} end)
    patch(Providers, :search_authors, fn _id, _query, _opts -> {:ok, []} end)
    patch(Providers, :author_details, fn _id, _author_id, _opts -> {:error, :not_stubbed} end)
    :ok
  end

  defp item do
    %InboxItem{
      path: "/downloads/The Way of Kings",
      files: ["/downloads/The Way of Kings/book.m4b"],
      tags: %{"book_title" => "The Way of Kings", "authors" => ["Brandon Sanderson"]}
    }
    |> Map.from_struct()
    |> then(&(%InboxItem{} |> InboxItem.changeset(&1) |> Repo.insert!()))
  end

  defp job(item, attempt \\ 1),
    do: %Oban.Job{args: %{"inbox_item_id" => item.id}, attempt: attempt, max_attempts: 8}

  describe "the job is not finished until every provider has answered" do
    # A match where one provider is rate-limited does not crash: records get
    # written, a draft gets staged, and the job reported success having got
    # less than it set out to get. Measured on a real batch, Hardcover failed
    # on 5 of 14 items and one ended up with no work candidates at all.
    @tag :capture_log
    test "a provider that couldn't be reached puts the job back on the queue" do
      patch(Providers, :search_books, fn id, _query, _opts ->
        if id == "rreading_glasses", do: {:error, :rate_limited}, else: {:ok, []}
      end)

      assert {:error, {:providers_unreached, unreached}} = RunMatch.perform(job(item()))
      assert "rreading_glasses" in unreached
    end

    # The partial result is already stored and stays stored, so each attempt
    # keeps whatever it got and re-asks only what it missed.
    @tag :capture_log
    test "what it did get is kept across the failure" do
      patch(Providers, :search_books, fn id, _query, _opts ->
        if id == "rreading_glasses", do: {:error, :rate_limited}, else: {:ok, []}
      end)

      item = item()
      assert {:error, _reason} = RunMatch.perform(job(item))

      item = Inbox.get_item!(item.id)
      assert item.matches
      assert item.draft
      assert Inbox.unreached_providers(item) == ["rreading_glasses"]
    end

    @tag :capture_log
    test "the last attempt keeps what it has rather than discarding the job" do
      patch(Providers, :search_books, fn id, _query, _opts ->
        if id == "rreading_glasses", do: {:error, :rate_limited}, else: {:ok, []}
      end)

      # a discarded job is deleted by the pruner within a day; the outcome is
      # on the item, where the form's "couldn't be reached — retry" chip reads
      # it, and that is the signal worth keeping
      assert :ok = RunMatch.perform(job(item(), 8))
    end

    test "every provider answering finishes the job" do
      patch(Providers, :search_books, fn _id, _query, _opts -> {:ok, []} end)

      assert :ok = RunMatch.perform(job(item()))
    end
  end

  # A retry that finally reaches a provider is pointless if the records it
  # returns never reach the form: `prepare_draft/1` leaves an existing draft
  # untouched, so the draft staged on attempt one would never see them.
  describe "a retry's records reach the draft" do
    @tag :capture_log
    test "matching re-derives a draft it already staged" do
      patch(Providers, :search_books, fn _id, _query, _opts -> {:error, :rate_limited} end)

      item = item()
      assert {:error, _reason} = RunMatch.perform(job(item))
      assert Inbox.get_item!(item.id).draft.work.title.value == "The Way of Kings"

      # the provider comes back, with a title of its own
      patch(Providers, :search_books, fn id, _query, _opts ->
        if id == "rreading_glasses" do
          {:ok,
           [
             %Ambry.Metadata.Provider.Book{
               provider: "rreading_glasses",
               id: "hc-1",
               title: "The Way of Kings",
               published: %Ambry.Metadata.Provider.PublishedDate{
                 date: ~D[2010-08-31],
                 display_format: :full
               },
               authors: [
                 %Ambry.Metadata.Provider.Contributor{name: "Brandon Sanderson", role: "author"}
               ]
             }
           ]}
        else
          {:ok, []}
        end
      end)

      assert :ok = RunMatch.perform(job(Inbox.get_item!(item.id), 2))

      # the record the retry finally got is on the draft, not just in matches
      draft = Inbox.get_item!(item.id).draft
      assert draft.work.published.value == "2010-08-31"
      assert draft.work.sources != []
    end
  end
end
