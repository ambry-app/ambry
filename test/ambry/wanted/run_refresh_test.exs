defmodule Ambry.Wanted.RunRefreshTest do
  @moduledoc """
  The worker exists for one thing arithmetic cannot do: notice that a
  publisher moved a date.
  """

  use Ambry.DataCase, async: false
  use Patch

  alias Ambry.Metadata.Provider
  alias Ambry.Wanted
  alias Ambry.Wanted.RunRefresh

  defp watch(date, overrides \\ %{}) do
    {:ok, watch} =
      Wanted.create_watch(
        Map.merge(
          %{
            provider: "audible",
            provider_id: "B0GPDBGTTL",
            expected_release_date: date,
            edition: %{
              title: "Blightfall",
              authors: ["Brandon Sanderson"],
              narrators: ["Eddie Lopez"],
              publisher: "Listening Library"
            }
          },
          overrides
        )
      )

    watch
  end

  defp provider_says(date, overrides \\ %{}) do
    book =
      Map.merge(
        %Provider.Book{
          provider: "audible",
          id: "B0GPDBGTTL",
          title: "Blightfall",
          narrators: [%{name: "Eddie Lopez"}],
          published: date && %Provider.PublishedDate{date: date, display_format: :full}
        },
        overrides
      )

    patch(Ambry.Metadata.Providers.Audible, :book_details, fn _asin, _config -> {:ok, book} end)
  end

  describe "due_for_refresh/1" do
    test "asks about what is nearly due" do
      near = watch(~D[2026-09-01], %{provider_id: "near"})
      _far = watch(~D[2027-06-01], %{provider_id: "far"})

      due = RunRefresh.due_for_refresh(~D[2026-08-22])

      assert Enum.map(due, & &1.id) == [near.id]
    end

    # A watch with no date is waiting for one, and the provider is the only
    # place it can come from.
    test "includes an undated watch" do
      undated = watch(nil, %{provider_id: "undated"})

      due = RunRefresh.due_for_refresh(~D[2026-08-22])

      assert Enum.map(due, & &1.id) == [undated.id]
    end

    test "a watch already past its date is still asked about, since that is when dates slip" do
      overdue = watch(~D[2026-08-01], %{provider_id: "overdue"})

      due = RunRefresh.due_for_refresh(~D[2026-08-22])

      assert Enum.map(due, & &1.id) == [overdue.id]
    end

    test "a settled watch is not asked about again" do
      watch = watch(~D[2026-09-01])
      {:ok, _} = Wanted.dismiss(watch)

      assert RunRefresh.due_for_refresh(~D[2026-08-22]) == []
    end
  end

  describe "refresh/1" do
    test "reports a date the publisher moved" do
      watch = watch(~D[2026-09-01])
      provider_says(~D[2026-11-03])

      assert {:moved, ~D[2026-09-01], ~D[2026-11-03]} = RunRefresh.refresh(watch)
      assert Wanted.get_watch!(watch.id).expected_release_date == ~D[2026-11-03]
    end

    test "says nothing changed when nothing did" do
      watch = watch(~D[2026-09-01])
      provider_says(~D[2026-09-01])

      assert RunRefresh.refresh(watch) == :unchanged
    end

    test "a date that appears for a watch that had none is a move" do
      watch = watch(nil)
      provider_says(~D[2026-12-01])

      assert {:moved, nil, ~D[2026-12-01]} = RunRefresh.refresh(watch)
    end

    # The operator's snapshot is not something to discard because a request
    # timed out.
    @tag :capture_log
    test "an unreachable provider leaves the watch exactly as it was" do
      watch = watch(~D[2026-09-01])

      patch(Ambry.Metadata.Providers.Audible, :book_details, fn _asin, _config ->
        {:error, :timeout}
      end)

      assert {:error, :timeout} = RunRefresh.refresh(watch)

      reloaded = Wanted.get_watch!(watch.id)
      assert reloaded.expected_release_date == ~D[2026-09-01]
      assert reloaded.edition.narrators == ["Eddie Lopez"]
    end

    # A thinner answer is a worse answer, not a correction.
    test "a provider that has since dropped a field does not blank what was kept" do
      watch = watch(~D[2026-09-01])
      provider_says(~D[2026-09-01], %{narrators: [], publisher: nil})

      assert RunRefresh.refresh(watch) == :unchanged

      reloaded = Wanted.get_watch!(watch.id)
      assert reloaded.edition.narrators == ["Eddie Lopez"]
      assert reloaded.edition.publisher == "Listening Library"
    end

    # A provider saying it came out is not the operator having it, and the nag
    # should be loudest exactly then.
    test "never settles a watch on the provider's say-so" do
      watch = watch(~D[2026-09-01])
      provider_says(~D[2020-01-01])

      RunRefresh.refresh(watch)

      assert Wanted.get_watch!(watch.id).status == :upcoming
    end
  end

  describe "perform/1" do
    test "counts what it checked and what moved" do
      watch(~D[2026-09-01])
      provider_says(~D[2026-11-03])

      assert {:ok, %{checked: 1, moved: 1, failed: 0}} =
               perform_job(RunRefresh, %{})
    end
  end
end
