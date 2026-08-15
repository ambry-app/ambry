defmodule Ambry.Inbox.ClaimsTest do
  use Ambry.DataCase

  alias Ambry.Inbox.AutoMatch
  alias Ambry.Inbox.Claims
  alias Ambry.Inbox.InboxItem

  # The item this whole feature was built for: the file's author tag holds the
  # name of the person who *read* it, and the narrator tag is empty.
  defp suitcase_clone(rejected \\ []) do
    %InboxItem{
      path: "The Suitcase Clone",
      files: ["The Suitcase Clone/Part01.mp3", "The Suitcase Clone/Part02.mp3"],
      rejected_claims: rejected,
      tags: %{
        "book_title" => "The Suitcase Clone",
        "authors" => ["Pavi Proczko"],
        "narrators" => [],
        "publisher" => "Macmillan Audio"
      }
    }
  end

  describe "tags/1" do
    test "a rejected tag is gone, and the rest are untouched" do
      assert %{"authors" => ["Pavi Proczko"], "book_title" => "The Suitcase Clone"} =
               Claims.tags(suitcase_clone())

      tags = Claims.tags(suitcase_clone(["tag:authors"]))

      refute Map.has_key?(tags, "authors")
      assert tags["book_title"] == "The Suitcase Clone"
      assert tags["publisher"] == "Macmillan Audio"
    end
  end

  describe "hints through the layer" do
    test "rejecting the author tag leaves the author unstated" do
      assert %{author: "Pavi Proczko"} = AutoMatch.hints(suitcase_clone())

      assert %{author: nil, title: "The Suitcase Clone"} =
               AutoMatch.hints(suitcase_clone(["tag:authors"]))
    end

    # The trap the release-name box exists for: rejecting the tag alone makes
    # the parser lift the same junk straight back out of the folder name, so a
    # single checkbox would have swapped one bad source for another.
    test "rejecting a tag falls through to the release name until that is rejected too" do
      item = %InboxItem{
        path: "Bafflegab Productions - The Hellbound Heart",
        tags: %{"book_title" => "The Hellbound Heart", "authors" => ["Bafflegab Productions"]}
      }

      assert %{author: "Bafflegab Productions"} = AutoMatch.hints(item)

      assert %{author: "Bafflegab Productions"} =
               AutoMatch.hints(%{item | rejected_claims: ["tag:authors"]})

      hints = AutoMatch.hints(%{item | rejected_claims: ["tag:authors", "name"]})

      assert hints.author == nil
      # and the title survives, because the tag still supplies it
      assert hints.title == "The Hellbound Heart"
    end

    test "rejecting reaches the back-match's haystack, not just the search" do
      assert AutoMatch.hints(suitcase_clone()).raw =~ "Pavi Proczko"
      refute AutoMatch.hints(suitcase_clone(["tag:authors"])).raw =~ "Pavi Proczko"

      assert AutoMatch.hints(suitcase_clone()).raw =~ "Part01"
      refute AutoMatch.hints(suitcase_clone(["files"])).raw =~ "Part01"
    end
  end

  describe "rows/1" do
    test "one row per claim the file actually makes" do
      rows = Claims.rows(suitcase_clone())
      keys = Enum.map(rows, & &1.key)

      assert "name" in keys
      assert "files" in keys
      assert "tag:authors" in keys
      # an empty tag is nothing to disagree with
      refute "tag:narrators" in keys
      assert Enum.all?(rows, & &1.accepted)
    end

    test "a rejected row says so" do
      rows = Claims.rows(suitcase_clone(["tag:authors"]))
      authors = Enum.find(rows, &(&1.key == "tag:authors"))

      refute authors.accepted
      # still shown: rejecting a claim is not forgetting it
      assert authors.value == "Pavi Proczko"
    end

    test "a description is stripped of markup and clipped" do
      item = %InboxItem{
        path: "Whatever",
        tags: %{
          "description" =>
            "<p><b>At last</b>, the story that definitively bridges " <>
              String.duplicate("the world ", 20)
        }
      }

      row = Enum.find(Claims.rows(item), &(&1.key == "tag:description"))

      refute row.value =~ "<"
      assert row.value =~ "At last, the story"
      assert String.length(row.value) <= 71
    end
  end

  describe "toggle/2" do
    test "adds, removes, and never duplicates" do
      item = suitcase_clone()

      assert Claims.toggle(item, "tag:authors") == ["tag:authors"]

      assert item |> struct(rejected_claims: ["tag:authors"]) |> Claims.toggle("tag:authors") ==
               []

      assert item
             |> struct(rejected_claims: ["name"])
             |> Claims.toggle("tag:authors") == ["name", "tag:authors"]
    end
  end
end
