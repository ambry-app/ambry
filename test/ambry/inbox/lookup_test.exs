defmodule Ambry.Inbox.LookupTest do
  @moduledoc """
  Asking providers things after an item has been matched.

  The boundary these tests exist to hold: everything here writes *evidence*
  and never a decision. New records appear un-ticked, and a record the draft
  already points at keeps its identity — otherwise a re-search would silently
  un-tick whatever the operator had chosen.
  """

  use Ambry.DataCase
  use Patch

  alias Ambry.Inbox
  alias Ambry.Inbox.Draft
  alias Ambry.Inbox.InboxItem
  alias Ambry.Metadata.Provider
  alias Ambry.Metadata.Providers
  alias Ambry.Repo

  setup do
    patch(Providers, :search_books, fn _id, _query, _opts -> {:ok, []} end)
    patch(Providers, :editions, fn _id, _work_id, _opts -> {:ok, []} end)
    patch(Providers, :book_details, fn _id, _book_id, _opts -> {:error, :not_stubbed} end)
    :ok
  end

  describe "research/3" do
    test "adds what it finds without disturbing what's ticked" do
      item = item_with_records()
      {:ok, item} = Inbox.prepare_draft(item)

      ticked = item.draft.work.sources
      assert ticked != []

      patch(Providers, :search_books, fn _id, _query, _opts ->
        {:ok, [book("A Book Nobody Guessed", ["Someone"])]}
      end)

      {:ok, item} = Inbox.research(item, "work", %{"title" => "something else"})

      titles = Enum.map(Draft.Seed.records(item, "work"), & &1["title"])
      assert "A Book Nobody Guessed" in titles
      # the original record is still there and still ticked
      assert "Leviathan Wakes" in titles
      assert item.draft.work.sources == ticked
    end

    test "remembers the query the operator wrote" do
      item = item_with_records()

      {:ok, item} =
        Inbox.research(item, "work", %{"title" => "Nemesis Games", "author" => "Corey"})

      assert get_in(item.matches, ["work", "query_fields"]) == %{
               "title" => "Nemesis Games",
               "author" => "Corey"
             }
    end

    test "an empty search does nothing at all" do
      item = item_with_records()
      before = item.matches

      {:ok, item} = Inbox.research(item, "work", %{"title" => "  ", "author" => ""})

      assert item.matches == before
    end
  end

  describe "retry_provider/3" do
    # A rate limit during matching used to cost an item that provider's records
    # until somebody re-ran the whole match.
    test "replaces the failure with what the provider says this time" do
      item =
        item_with_records(
          providers: [
            %{
              "id" => "hardcover",
              "name" => "Hardcover",
              "status" => "failed",
              "count" => 0,
              "reason" => ":rate_limited"
            }
          ]
        )

      patch(Providers, :search_books, fn _id, _query, _opts ->
        {:ok, [book("Leviathan Wakes", ["James S.A. Corey"])]}
      end)

      {:ok, item} = Inbox.retry_provider(item, "work", "hardcover")

      outcomes = get_in(item.matches, ["work", "providers"])
      assert [%{"id" => "hardcover", "status" => "ok"}] = outcomes
    end

    test "an unknown provider is a no-op rather than a crash" do
      item = item_with_records()

      assert {:ok, ^item} = Inbox.retry_provider(item, "work", "no-such-provider")
    end
  end

  describe "hydrate_record/3" do
    test "fills in a thin record and marks it fetched" do
      item = item_with_records()

      patch(Providers, :book_details, fn _id, _book_id, _opts ->
        {:ok, %Provider.Book{provider: "test", id: "hc-1", description: "The full description"}}
      end)

      ref = {"provider:hardcover", "hc-1"}
      {:ok, item} = Inbox.hydrate_record(item, "work", ref)

      assert [record] = Draft.Seed.records(item, "work")
      assert record["description"] == "The full description"
      assert record["hydrated"]
    end

    test "a record already fetched is left alone" do
      item = item_with_records(hydrated: true)

      patch(Providers, :book_details, fn _id, _book_id, _opts ->
        flunk("should not re-fetch a record that is already hydrated")
      end)

      assert {:ok, _item} = Inbox.hydrate_record(item, "work", {"provider:hardcover", "hc-1"})
    end
  end

  defp item_with_records(opts \\ []) do
    record =
      %{
        "source" => "provider:hardcover",
        "provider_name" => "Hardcover",
        "id" => "hc-1",
        "title" => "Leviathan Wakes",
        "authors" => ["James S.A. Corey"],
        "published" => "2011-06-15",
        "published_format" => "full",
        "score" => 0.95
      }
      |> then(&if Keyword.get(opts, :hydrated), do: Map.put(&1, "hydrated", true), else: &1)

    %InboxItem{}
    |> InboxItem.changeset(%{
      path: "/downloads/Leviathan Wakes",
      files: ["/downloads/Leviathan Wakes/book.m4b"],
      matches: %{
        "work" => %{
          "candidates" => [record],
          "local" => [],
          "confidence" => 0.95,
          "providers" => Keyword.get(opts, :providers, [])
        },
        "recording" => %{"candidates" => []}
      }
    })
    |> Repo.insert!()
  end

  defp book(title, authors) do
    %Provider.Book{
      provider: "test",
      id: "id-#{:erlang.phash2(title)}",
      title: title,
      authors: Enum.map(authors, &%Provider.Contributor{name: &1, role: "author"})
    }
  end
end
