defmodule Ambry.Wanted.InboxLoopTest do
  @moduledoc """
  The loop that makes a watch more than a note: the queue recognises what the
  operator was waiting for, and importing it turns the nag off.
  """

  use Ambry.DataCase, async: false

  alias Ambry.Inbox.AutoMatch
  alias Ambry.Wanted

  defp watch(overrides \\ %{}) do
    {:ok, watch} =
      Wanted.create_watch(
        Map.merge(
          %{
            provider: "audible",
            provider_id: "B0GPDBGTTL",
            expected_release_date: ~D[2026-09-01],
            edition: %{title: "Blightfall", authors: ["Brandon Sanderson"]}
          },
          overrides
        )
      )

    watch
  end

  defp record(source, id, extra \\ %{}) do
    Map.merge(%{"source" => source, "id" => id, "score" => 0.9}, extra)
  end

  describe "open_refs/0" do
    test "is what is still being waited on, not what has been answered" do
      _open = watch()
      settled = watch(%{provider_id: "settled"})
      {:ok, _} = Wanted.mark_released(settled)

      assert Wanted.open_refs() == MapSet.new([{"audible", "B0GPDBGTTL"}])
    end
  end

  describe "mark_wanted/2" do
    test "marks the candidate the operator went looking for" do
      refs = MapSet.new([{"audible", "B0GPDBGTTL"}])

      marked =
        AutoMatch.mark_wanted(
          [record("audible", "B0GPDBGTTL"), record("audible", "other")],
          refs
        )

      assert [%{"wanted" => true}, second] = marked
      refute Map.has_key?(second, "wanted")
    end

    test "leaves every candidate alone when nothing is being watched" do
      candidates = [record("audible", "B0GPDBGTTL")]

      assert AutoMatch.mark_wanted(candidates, MapSet.new()) == candidates
    end

    # A watch is evidence about the operator's intent, not about the file.
    test "does not touch the score" do
      refs = MapSet.new([{"audible", "B0GPDBGTTL"}])

      [marked] = AutoMatch.mark_wanted([record("audible", "B0GPDBGTTL")], refs)

      assert marked["score"] == 0.9
    end
  end

  describe "order_candidates/1" do
    test "a wanted recording leads among equals" do
      ordered =
        AutoMatch.order_candidates([
          record("audible", "rival", %{"score" => 1.0}),
          record("audible", "wanted", %{"score" => 1.0, "wanted" => true})
        ])

      assert Enum.map(ordered, & &1["id"]) == ["wanted", "rival"]
    end

    test "but never outranks a better score" do
      ordered =
        AutoMatch.order_candidates([
          record("audible", "wanted", %{"score" => 0.5, "wanted" => true}),
          record("audible", "better", %{"score" => 0.9})
        ])

      assert Enum.map(ordered, & &1["id"]) == ["better", "wanted"]
    end

    # Corroboration says the record fits the file; a watch says the operator
    # went looking for it. Among equals the second is the stronger statement.
    test "leads a candidate the file merely corroborated" do
      ordered =
        AutoMatch.order_candidates([
          record("audible", "corroborated", %{
            "score" => 1.0,
            "narrator_evidence" => "supported"
          }),
          record("audible", "wanted", %{"score" => 1.0, "wanted" => true})
        ])

      assert Enum.map(ordered, & &1["id"]) == ["wanted", "corroborated"]
    end
  end

  describe "settle/2" do
    setup do
      %{media: insert(:media, book: build(:book))}
    end

    test "settles the watch the import answered", %{media: media} do
      watch = watch()

      assert [settled] = Wanted.settle([{"audible", "B0GPDBGTTL"}], media)
      assert settled.id == watch.id

      reloaded = Wanted.get_watch!(watch.id)
      assert reloaded.status == :released
      assert reloaded.media_id == media.id
    end

    # A candidate that was offered and passed over is no evidence that this
    # file is that recording.
    test "leaves a watch the import did not adopt", %{media: media} do
      watch = watch()

      assert Wanted.settle([{"audible", "something-else"}], media) == []
      assert Wanted.get_watch!(watch.id).status == :upcoming
    end

    test "one import can answer watches on several provider records", %{media: media} do
      one = watch()
      two = watch(%{provider: "hardcover", provider_id: "33170376"})

      settled = Wanted.settle([{"audible", "B0GPDBGTTL"}, {"hardcover", "33170376"}], media)

      assert Enum.map(settled, & &1.id) |> Enum.sort() == Enum.sort([one.id, two.id])
    end

    test "an already-settled watch is not settled twice", %{media: media} do
      watch = watch()
      {:ok, _} = Wanted.dismiss(watch)

      assert Wanted.settle([{"audible", "B0GPDBGTTL"}], media) == []
      assert Wanted.get_watch!(watch.id).status == :dismissed
    end
  end
end
