defmodule Ambry.WantedTest do
  use Ambry.DataCase

  alias Ambry.Wanted
  alias Ambry.Wanted.Edition
  alias Ambry.Wanted.Watch

  defp attrs(overrides \\ %{}) do
    Map.merge(
      %{
        provider: "audible",
        provider_id: "B0FKVNLXQS",
        expected_release_date: ~D[2026-09-29],
        edition: %{
          title: "The Velvet Knife",
          authors: ["Maureen Johnson"],
          narrators: ["Emily Ellet"],
          publisher: "Harper Audio",
          asin: "B0FKVNLXQS"
        }
      },
      overrides
    )
  end

  describe "create_watch/1" do
    test "keeps the provider's record as it was when it was chosen" do
      {:ok, watch} = Wanted.create_watch(attrs())

      assert watch.edition.title == "The Velvet Knife"
      assert watch.edition.narrators == ["Emily Ellet"]
      assert watch.status == :upcoming
    end

    test "a recording with no date is still a watch" do
      {:ok, watch} = Wanted.create_watch(attrs(%{expected_release_date: nil}))

      assert watch.expected_release_date == nil
      assert watch.status == :upcoming
    end

    test "answers with the existing watch rather than an error when already watching" do
      {:ok, first} = Wanted.create_watch(attrs())

      assert {:error, :already_watching, existing} = Wanted.create_watch(attrs())
      assert existing.id == first.id
    end

    test "the same recording from a different provider is a different watch" do
      {:ok, _audible} = Wanted.create_watch(attrs())

      assert {:ok, hardcover} =
               Wanted.create_watch(attrs(%{provider: "hardcover", provider_id: "33170376"}))

      assert hardcover.provider == "hardcover"
    end

    test "requires an edition" do
      assert {:error, changeset} = Wanted.create_watch(%{provider: "audible", provider_id: "x"})
      assert %{edition: _} = errors_on(changeset)
    end
  end

  describe "runtime" do
    test "an audiobook's length is part of what was chosen" do
      {:ok, watch} =
        Wanted.create_watch(
          attrs(%{edition: %{title: "The Velvet Knife", duration_seconds: 36_000}})
        )

      assert watch.edition.duration_seconds == 36_000
      assert Edition.runtime(watch.edition) == "10h"
    end

    test "reads in hours and minutes, the way a recording is talked about" do
      assert Edition.runtime(%Edition{duration_seconds: 37_920}) == "10h 32m"
      assert Edition.runtime(%Edition{duration_seconds: 3600}) == "1h"
      assert Edition.runtime(%Edition{duration_seconds: 900}) == "15m"
    end

    # Not every provider record has one -- seven of Hardcover's twelve
    # Neuromancer audio editions do. An absent runtime is reported as absent.
    test "a provider that gave no runtime leaves it absent rather than zero" do
      assert Edition.runtime(%Edition{duration_seconds: nil}) == nil
      assert Edition.runtime(%Edition{duration_seconds: 0}) == nil
    end
  end

  describe "due?/2" do
    test "is true once the expected date has arrived" do
      {:ok, watch} = Wanted.create_watch(attrs(%{expected_release_date: ~D[2026-09-29]}))

      refute Watch.due?(watch, ~D[2026-09-28])
      assert Watch.due?(watch, ~D[2026-09-29])
      assert Watch.due?(watch, ~D[2026-10-05])
    end

    test "a watch with no date never becomes due" do
      {:ok, watch} = Wanted.create_watch(attrs(%{expected_release_date: nil}))

      refute Watch.due?(watch, ~D[2099-01-01])
    end

    test "a settled watch is not due, however old its date" do
      {:ok, watch} = Wanted.create_watch(attrs(%{expected_release_date: ~D[2020-01-01]}))
      {:ok, released} = Wanted.mark_released(watch)
      {:ok, dismissed} = Wanted.dismiss(watch)

      refute Watch.due?(released, ~D[2026-09-29])
      refute Watch.due?(dismissed, ~D[2026-09-29])
    end
  end

  describe "list_watches/1" do
    test "puts what is due first, then what is coming soonest" do
      {:ok, _far} = Wanted.create_watch(attrs(%{provider_id: "far", edition: edition("Far")}))

      {:ok, _soon} =
        Wanted.create_watch(
          attrs(%{
            provider_id: "soon",
            expected_release_date: ~D[2026-09-01],
            edition: edition("Soon")
          })
        )

      {:ok, _overdue} =
        Wanted.create_watch(
          attrs(%{
            provider_id: "overdue",
            expected_release_date: ~D[2026-01-01],
            edition: edition("Overdue")
          })
        )

      titles =
        [today: ~D[2026-08-22]]
        |> Wanted.list_watches()
        |> Enum.map(& &1.edition.title)

      assert titles == ["Overdue", "Soon", "Far"]
    end

    test "an undated watch sorts after the dated ones" do
      {:ok, _dated} =
        Wanted.create_watch(attrs(%{provider_id: "dated", edition: edition("Dated")}))

      {:ok, _undated} =
        Wanted.create_watch(
          attrs(%{
            provider_id: "undated",
            expected_release_date: nil,
            edition: edition("Undated")
          })
        )

      titles =
        [today: ~D[2026-08-22]]
        |> Wanted.list_watches()
        |> Enum.map(& &1.edition.title)

      assert titles == ["Dated", "Undated"]
    end

    test "settled watches sink below the ones still waiting" do
      {:ok, waiting} =
        Wanted.create_watch(attrs(%{provider_id: "waiting", edition: edition("Waiting")}))

      {:ok, done} = Wanted.create_watch(attrs(%{provider_id: "done", edition: edition("Done")}))
      {:ok, _} = Wanted.mark_released(done)

      titles =
        [today: ~D[2026-08-22]]
        |> Wanted.list_watches()
        |> Enum.map(& &1.edition.title)

      assert titles == ["Waiting", "Done"]
      assert waiting.status == :upcoming
    end
  end

  describe "summary/1" do
    test "counts only what is due, and names what is coming next" do
      {:ok, _overdue} =
        Wanted.create_watch(
          attrs(%{
            provider_id: "overdue",
            expected_release_date: ~D[2026-08-01],
            edition: edition("Overdue")
          })
        )

      {:ok, _next} =
        Wanted.create_watch(
          attrs(%{
            provider_id: "next",
            expected_release_date: ~D[2026-09-01],
            edition: edition("Blightfall")
          })
        )

      summary = Wanted.summary(~D[2026-08-22])

      assert summary.due_count == 1
      assert summary.upcoming_count == 2
      assert summary.next.edition.title == "Blightfall"
    end

    test "nothing due and nothing coming is not an error state" do
      summary = Wanted.summary(~D[2026-08-22])

      assert summary.due_count == 0
      assert summary.upcoming_count == 0
      assert summary.next == nil
    end

    test "a dismissed watch stops counting toward the nag" do
      {:ok, watch} =
        Wanted.create_watch(attrs(%{expected_release_date: ~D[2026-01-01]}))

      assert Wanted.summary(~D[2026-08-22]).due_count == 1

      {:ok, _} = Wanted.dismiss(watch)

      assert Wanted.summary(~D[2026-08-22]).due_count == 0
    end
  end

  describe "mark_released/2" do
    test "links the recording that answered the watch" do
      media = insert(:media, book: build(:book))
      {:ok, watch} = Wanted.create_watch(attrs())

      {:ok, released} = Wanted.mark_released(watch, media)

      assert released.status == :released
      assert released.media_id == media.id
    end

    test "settles without one, for a book the operator knows is out but hasn't got" do
      {:ok, watch} = Wanted.create_watch(attrs())

      {:ok, released} = Wanted.mark_released(watch)

      assert released.status == :released
      assert released.media_id == nil
    end
  end

  describe "reopen/1" do
    test "puts a settled watch back into waiting" do
      {:ok, watch} = Wanted.create_watch(attrs())
      {:ok, dismissed} = Wanted.dismiss(watch)
      {:ok, reopened} = Wanted.reopen(dismissed)

      assert reopened.status == :upcoming
    end
  end

  defp edition(title) do
    %{title: title, authors: ["Someone"], narrators: ["A Reader"]}
  end
end
