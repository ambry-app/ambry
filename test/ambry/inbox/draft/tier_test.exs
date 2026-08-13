defmodule Ambry.Inbox.Draft.TierTest do
  @moduledoc """
  The four words the whole form speaks.

  Settled-versus-waiting answered "can this be imported" and threw away the
  question the operator actually asks of a machine-matched import: has anyone
  looked at this yet.
  """
  use ExUnit.Case, async: true

  alias Ambry.Inbox.Draft.Candidate
  alias Ambry.Inbox.Draft.Credit
  alias Ambry.Inbox.Draft.Field
  alias Ambry.Inbox.Draft.Recording
  alias Ambry.Inbox.Draft.Tier
  alias Ambry.Inbox.Draft.Work

  defp candidate(value), do: %Candidate{value: value, source: "provider:hardcover", key: "k"}

  describe "of/1" do
    test "a field the machine settled and nobody touched is unreviewed" do
      assert Tier.of(%Field{approved: true, curated: false}) == :unreviewed
    end

    test "a field a human touched is reviewed" do
      assert Tier.of(%Field{approved: true, curated: true}) == :reviewed
    end

    # The distinction the fourth tier buys: taking the machine's own value
    # still counts as having looked, because the operator did.
    test "reviewed does not depend on the value differing from the machine's" do
      machine = %Field{approved: true, curated: false, candidates: [candidate("Dune")]}
      looked = %{machine | curated: true}

      assert Tier.of(machine) == :unreviewed
      assert Tier.of(looked) == :reviewed
      assert Field.value(machine) == Field.value(looked)
    end

    test "an unsettled field waits" do
      assert Tier.of(%Field{approved: false, candidates: [candidate("Dune")]}) == :waiting
    end

    # Red, and rare: measured across 335 live drafts it was 7 fields in 4,817,
    # every one of them a missing publication date, which refuses the import.
    test "a required field nothing proposed is blocked" do
      assert Tier.of(%Field{approved: false, required: true, candidates: []}) == :blocked
    end

    test "an optional field nothing proposed merely waits" do
      assert Tier.of(%Field{approved: false, required: false, candidates: []}) == :waiting
    end

    test "a credit carries its own state and its own touch" do
      ambiguous = %Credit{approved: false, candidates: [%{}, %{}]}

      assert Tier.of(ambiguous) == :waiting
      assert Tier.of(%{ambiguous | curated: true}) == :waiting
    end
  end

  describe "a level asks two questions" do
    # Collapsing both into one number made the two cards identical, which
    # tells the operator something needs them without saying which.
    test "evidence and identity are tiered separately" do
      work = %Work{
        approved: true,
        curated: false,
        doubt: :low_confidence,
        evidence_curated: false
      }

      assert Tier.of_evidence(work) == :waiting
      assert Tier.of_identity(work) == :unreviewed
    end

    test "the level itself is the worse of the two" do
      work = %Work{approved: true, curated: true, doubt: :low_confidence, evidence_curated: false}

      assert Tier.of_identity(work) == :reviewed
      assert Tier.of(work) == :waiting
    end

    # "Found nothing" is an answer, not a failure — there is nothing to choose
    # between, and plenty of narrators are in no database at all.
    test "a level that found nothing is settled" do
      assert Tier.of(%Recording{approved: true, doubt: :nothing_found}) == :unreviewed
    end

    test "a recording is never linked, so it has no identity question" do
      recording = %Recording{approved: true, doubt: :none, evidence_curated: true}

      assert Tier.of(recording) == Tier.of_evidence(recording)
      assert Tier.of(recording) == :reviewed
    end
  end

  describe "worst/1" do
    test "ranks blocked over waiting over unreviewed over reviewed" do
      assert Tier.worst([:reviewed, :unreviewed]) == :unreviewed
      assert Tier.worst([:reviewed, :unreviewed, :waiting]) == :waiting
      assert Tier.worst([:waiting, :blocked]) == :blocked
    end

    # A card claiming the operator has been through it while one field inside
    # still waits is the aggregate lying.
    test "reviewed only when every child is" do
      assert Tier.worst([:reviewed, :reviewed]) == :reviewed
      assert Tier.worst([:reviewed, :unreviewed]) != :reviewed
    end

    # "Not in a series" is something the machine worked out and nobody
    # confirmed, not something a human decided.
    test "an empty list is unreviewed" do
      assert Tier.worst([]) == :unreviewed
    end

    test "of_all/1 tiers a list of decisions together" do
      fields = [%Field{approved: true, curated: true}, %Field{approved: false, required: true}]

      assert Tier.of_all(fields) == :blocked
    end
  end

  describe "outstanding?/1" do
    # The goal of an import is no amber and no red — never "all reviewed", or
    # every import becomes a chore of re-picking values that were right.
    test "only blocked and waiting want the operator" do
      assert Tier.outstanding?(:blocked)
      assert Tier.outstanding?(:waiting)
      refute Tier.outstanding?(:unreviewed)
      refute Tier.outstanding?(:reviewed)
    end
  end
end
