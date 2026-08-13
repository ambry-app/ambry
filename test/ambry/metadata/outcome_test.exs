defmodule Ambry.Metadata.OutcomeTest do
  @moduledoc """
  The vocabulary every fan-out reports in.

  The ids matter more than they look: the retry chip carries one back, and a
  chip that re-ran the wrong kind of call would report success having fixed
  nothing.
  """
  use ExUnit.Case, async: true

  alias Ambry.Metadata.Outcome
  alias Ambry.Metadata.Registry

  defp entry, do: %Registry.Entry{id: "hardcover", display_name: "Hardcover"}

  # Not every error is a failure to reach a provider, and treating them alike
  # put a red "couldn't be reached, retry" chip on items whose retry could
  # never succeed — and kept the matching job re-queuing itself for as long
  # as it had attempts left.
  describe "from_error/3" do
    test "a provider that cannot be asked reports nothing at all" do
      assert Outcome.from_error(entry(), :unsupported_capability, :details) == nil
      assert Outcome.from_error(entry(), :provider_disabled, :details) == nil
      assert Outcome.from_error(entry(), :provider_not_configured) == nil
    end

    # The provider answered. "It has no such record" is a count of zero, and
    # a retry will get the same definite answer every time.
    test "not-found is an answer, not a failure" do
      assert %{"id" => "hardcover:details", "status" => "ok", "count" => 0} =
               Outcome.from_error(entry(), :not_found, :details)
    end

    test "anything else is a failure worth retrying" do
      assert %{"status" => "failed", "reason" => ":rate_limited"} =
               Outcome.from_error(entry(), :rate_limited, :details)
    end
  end

  describe "ids" do
    test "a search is recorded under the provider's own id" do
      assert Outcome.id("hardcover") == "hardcover"
      assert Outcome.ok(entry(), 3)["id"] == "hardcover"
    end

    # Sharing one id meant the last write won, so a rate-limited details call
    # vanished behind the search that had already said `ok`.
    test "every other kind of call gets its own" do
      assert Outcome.id("hardcover", :details) == "hardcover:details"
      assert Outcome.id("hardcover", :editions) == "hardcover:editions"
      assert Outcome.ok(entry(), 1, :details)["id"] == "hardcover:details"
    end

    test "split/1 recovers the provider and what it was asked" do
      assert Outcome.split("hardcover") == {"hardcover", :search}
      assert Outcome.split("hardcover:details") == {"hardcover", :details}
      assert Outcome.split("hardcover:editions") == {"hardcover", :editions}
    end

    # A provider id that happens to contain a colon is a provider id, not a
    # kind — guessing otherwise would send a retry to a provider that doesn't
    # exist.
    test "an unknown suffix is part of the provider id" do
      assert Outcome.split("some:provider") == {"some:provider", :search}
    end

    test "an id survives a round trip" do
      for kind <- [:search, :details, :editions, :chapters] do
        assert Outcome.split(Outcome.id("hardcover", kind)) == {"hardcover", kind}
      end
    end
  end

  describe "what a chip reads" do
    test "the kind is named, so two chips from one provider are tellable apart" do
      assert Outcome.ok(entry(), 2)["name"] == "Hardcover"
      assert Outcome.ok(entry(), 2, :details)["name"] == "Hardcover details"
      assert Outcome.ok(entry(), 2, :editions)["name"] == "Hardcover editions"
    end

    test "a failure carries a reason short enough for a tooltip" do
      outcome = Outcome.failed(entry(), String.duplicate("very long ", 100))

      assert outcome["status"] == "failed"
      assert outcome["count"] == 0
      assert String.length(outcome["reason"]) <= 200
      assert Outcome.failed?(outcome)
    end

    test "an answer is not a failure" do
      refute Outcome.failed?(Outcome.ok(entry(), 0))
    end
  end
end
