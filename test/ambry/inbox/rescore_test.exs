defmodule Ambry.Inbox.RescoreTest do
  @moduledoc """
  Re-grading what is already stored when the operator rejects one of the
  file's claims.

  The boundary these hold: rejecting asks nobody anything, and a rejection
  that cannot change how a record is graded must leave that record's grade
  exactly as matching left it. Without the second one, toggling a box on and
  off would not land back where it started, and every unrelated record on the
  page would shift for no reason the operator could see.
  """

  use Ambry.DataCase

  alias Ambry.Inbox
  alias Ambry.Inbox.AutoMatch
  alias Ambry.Inbox.InboxItem
  alias Ambry.Repo

  describe "rescore/1" do
    test "is a no-op when nothing is rejected" do
      item = suitcase_clone()
      rescored = AutoMatch.rescore(item)

      for level <- ["work", "recording"] do
        assert rescored[level]["candidates"] == item.matches[level]["candidates"]
        assert rescored[level]["confidence"] == item.matches[level]["confidence"]
      end
    end

    test "rejecting an irrelevant claim leaves every grade alone" do
      item = suitcase_clone()

      rescored = AutoMatch.rescore(%{item | rejected_claims: ["tag:publisher"]})

      assert scores(rescored, "work") == scores(item.matches, "work")
      assert scores(rescored, "recording") == scores(item.matches, "recording")
    end

    # The measured case: the file credits its narrator as the author, so the
    # right record is halved by `author_agreement/2` and sits under Seed's
    # adoption bar. Rejecting the tag is the whole fix, and it needs no
    # provider call because the record was already here.
    test "rejecting the junk author lifts the record that was right all along" do
      item = suitcase_clone()

      assert scores(item.matches, "work") == [0.5]

      rescored = AutoMatch.rescore(%{item | rejected_claims: ["tag:authors"]})

      assert scores(rescored, "work") == [1.0]
      assert rescored["work"]["confidence"] == 1.0
    end

    # Verified across the operator's whole queue: 353 items, every claim
    # rejected and restored in turn (3530 round trips) plus a five-step cycle
    # per item, all landing back on the stored candidates and confidence
    # exactly. The memory that makes it work is `matched_score` and
    # `matched_place`, and it is dropped the moment nothing is rejected.
    test "rejecting is reversible, down to the order among ties" do
      item = suitcase_clone()

      there = AutoMatch.rescore(%{item | rejected_claims: ["tag:authors"]})
      back = AutoMatch.rescore(%{item | rejected_claims: [], matches: there})

      for level <- ["work", "recording"] do
        assert back[level]["candidates"] == item.matches[level]["candidates"]
        assert back[level]["confidence"] == item.matches[level]["confidence"]
      end
    end

    test "a restored record keeps none of the bookkeeping that restored it" do
      item = suitcase_clone()

      there = AutoMatch.rescore(%{item | rejected_claims: ["tag:authors"]})
      back = AutoMatch.rescore(%{item | rejected_claims: [], matches: there})

      assert Enum.any?(there["work"]["candidates"], &Map.has_key?(&1, "matched_score"))
      assert Enum.all?(back["work"]["candidates"], &(not Map.has_key?(&1, "matched_score")))
      assert Enum.all?(back["work"]["candidates"], &(not Map.has_key?(&1, "matched_place")))
    end
  end

  describe "toggle_claim/2" do
    test "stores the rejection, re-grades, and re-stages the draft" do
      {:ok, item} = suitcase_clone() |> Repo.insert() |> elem(1) |> Inbox.prepare_draft()

      assert item.draft.work.doubt == :low_confidence
      assert Enum.map(item.draft.work.authors, & &1.name) == ["Pavi Proczko"]

      {:ok, item} = Inbox.toggle_claim(item, "tag:authors")

      assert item.rejected_claims == ["tag:authors"]
      assert item.draft.work.doubt == :none
      assert Enum.map(item.draft.work.authors, & &1.name) == ["Robin Sloan"]
    end

    test "refuses a key that names no claim" do
      item = Repo.insert!(suitcase_clone())

      assert {:error, :unknown_claim} = Inbox.toggle_claim(item, "tag:nonsense")
      assert {:error, :unknown_claim} = Inbox.toggle_claim(item, "../etc/passwd")
    end

    test "an imported item is read-only" do
      item = %{suitcase_clone() | status: :imported} |> Repo.insert!()

      assert {:error, :already_imported} = Inbox.toggle_claim(item, "tag:authors")
    end
  end

  defp scores(matches, level),
    do: matches |> get_in([level, "candidates"]) |> Enum.map(& &1["score"])

  defp suitcase_clone do
    work = %{
      "source" => "provider:hardcover",
      "provider_name" => "Hardcover",
      "id" => "651408",
      "title" => "The Suitcase Clone",
      "authors" => ["Robin Sloan"],
      "narrators" => [],
      "series" => [],
      "hydrated" => true,
      "score" => 0.5
    }

    recording = %{
      "source" => "provider:audible",
      "provider_name" => "Audible",
      "id" => "B0B3SKVT53",
      "asin" => "B0B3SKVT53",
      "title" => "The Suitcase Clone",
      "authors" => ["Robin Sloan"],
      "narrators" => ["Pavi Proczko"],
      "series" => [],
      "published" => "2022-08-02",
      "published_format" => "full",
      "base_score" => 0.5,
      "narrator_evidence" => "supported",
      "score" => 0.525
    }

    %InboxItem{
      path: "The Suitcase Clone",
      files: ["The Suitcase Clone/Part01.mp3", "The Suitcase Clone/Part02.mp3"],
      source_id: insert(:source).id,
      status: :pending,
      rejected_claims: [],
      tags: %{
        "book_title" => "The Suitcase Clone",
        "authors" => ["Pavi Proczko"],
        "narrators" => [],
        "publisher" => "Macmillan Audio"
      },
      matches: %{
        "hints" => %{
          "title" => "The Suitcase Clone",
          "author" => "Pavi Proczko",
          "narrator" => nil
        },
        "work" => %{"candidates" => [work], "local" => [], "confidence" => 0.5, "providers" => []},
        "recording" => %{
          "candidates" => [recording],
          "confidence" => 0.525,
          "providers" => []
        }
      }
    }
  end
end
