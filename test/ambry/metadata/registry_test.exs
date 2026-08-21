defmodule Ambry.Metadata.RegistryTest do
  use Ambry.DataCase

  alias Ambry.Metadata.Cache
  alias Ambry.Metadata.Registry

  test "all/0 returns every known provider enabled by default, in priority order" do
    entries = Registry.all()

    assert Enum.map(entries, & &1.id) ==
             ["rreading_glasses", "hardcover", "audible", "audnexus", "wikidata", "tmdb"]

    assert Enum.all?(entries, & &1.enabled)
  end

  test "providers requiring config are unavailable until configured" do
    {:ok, entry} = Registry.fetch("hardcover")
    refute entry.available

    # unavailable providers are excluded from enabled/1 (import forms)...
    refute "hardcover" in Enum.map(Registry.enabled(level: :work), & &1.id)

    # ...until a token is stored
    {:ok, _row} = Registry.update("hardcover", %{config: %{"api_token" => "h.p.s"}})
    assert "hardcover" in Enum.map(Registry.enabled(level: :work), & &1.id)
  end

  test "default configs come from the provider's config fields" do
    {:ok, entry} = Registry.fetch("rreading_glasses")

    assert entry.config == %{base_url: "https://api.bookinfo.pro"}
  end

  test "enabled/1 filters by level and capability" do
    assert ["rreading_glasses"] = Enum.map(Registry.enabled(level: :work), & &1.id)

    assert ["audnexus"] = Enum.map(Registry.enabled(capability: :chapters), & &1.id)

    assert ["rreading_glasses", "audnexus", "wikidata"] =
             Enum.map(Registry.enabled(capability: :author_search), & &1.id)

    # tmdb is person-level too but unavailable until an API key is stored
    assert ["wikidata"] = Enum.map(Registry.enabled(level: :person), & &1.id)

    {:ok, _row} = Registry.update("tmdb", %{config: %{"api_key" => "k"}})
    assert ["wikidata", "tmdb"] = Enum.map(Registry.enabled(level: :person), & &1.id)
  end

  test "update/2 persists enabled flag and priority" do
    {:ok, _row} = Registry.update("audible", %{enabled: false})
    {:ok, entry} = Registry.fetch("audible")

    refute entry.enabled
    assert Registry.enabled(level: :recording) |> Enum.map(& &1.id) == ["audnexus"]
  end

  test "update/2 stores config overrides and drops unknown keys" do
    {:ok, _row} =
      Registry.update("rreading_glasses", %{
        config: %{"base_url" => "http://rg.local:8788", "bogus" => "x"}
      })

    {:ok, entry} = Registry.fetch("rreading_glasses")

    assert entry.config == %{base_url: "http://rg.local:8788"}
  end

  test "blank config values fall back to defaults" do
    {:ok, _row} = Registry.update("rreading_glasses", %{config: %{"base_url" => ""}})
    {:ok, entry} = Registry.fetch("rreading_glasses")

    assert entry.config == %{base_url: "https://api.bookinfo.pro"}
  end

  # The cache keys on the provider and the question and nothing else, so a
  # question already asked kept answering the old way for the rest of its TTL
  # — a week for searches. The operator widened Audible from `us` to
  # `us, uk`, searched a book they had searched before, and got the US
  # catalog's answer back (2026-08-21).
  test "changing what a provider is asked forgets what it answered before" do
    Cache.fetch("audible:search_books:q:x", fn -> {:ok, [:stale]} end)
    assert {:ok, [:stale]} = Cache.fetch("audible:search_books:q:x", fn -> {:ok, [:fresh]} end)

    {:ok, _row} = Registry.update("audible", %{config: %{"marketplaces" => "us, uk"}})

    assert {:ok, [:fresh]} = Cache.fetch("audible:search_books:q:x", fn -> {:ok, [:fresh]} end)
  end

  # Neither changes what a question means, and emptying a provider's cache
  # for a reorder would cost a round of lookups for nothing.
  test "enabling, disabling and reordering keep what a provider answered" do
    Cache.fetch("audible:search_books:q:x", fn -> {:ok, [:stale]} end)

    {:ok, _row} = Registry.update("audible", %{enabled: false})
    {:ok, _row} = Registry.update("audible", %{enabled: true, priority: 9})

    assert {:ok, [:stale]} = Cache.fetch("audible:search_books:q:x", fn -> {:ok, [:fresh]} end)
  end

  # Writing the same setting again is not a change, and the operator who
  # opens the settings and presses Save should not pay for a fresh round of
  # provider calls.
  test "saving a config unchanged keeps what a provider answered" do
    {:ok, _row} = Registry.update("audible", %{config: %{"marketplaces" => "us, uk"}})
    Cache.fetch("audible:search_books:q:x", fn -> {:ok, [:stale]} end)

    {:ok, _row} = Registry.update("audible", %{config: %{"marketplaces" => "us, uk"}})

    assert {:ok, [:stale]} = Cache.fetch("audible:search_books:q:x", fn -> {:ok, [:fresh]} end)
  end

  test "fetch/1 returns an error for unknown providers" do
    assert {:error, :unknown_provider} = Registry.fetch("goodreads")
  end

  # Reordering providers used to write an empty config, silently destroying
  # the operator's API token — the only symptom being the provider quietly
  # going unavailable later.
  test "reordering a provider keeps its configured secrets" do
    {:ok, _row} = Registry.update("hardcover", %{config: %{"api_token" => "h.p.s"}})

    {:ok, _row} = Registry.update("hardcover", %{priority: 0})

    {:ok, entry} = Registry.fetch("hardcover")
    assert entry.config.api_token == "h.p.s"
  end

  test "toggling a provider keeps its configured secrets" do
    {:ok, _row} = Registry.update("hardcover", %{config: %{"api_token" => "h.p.s"}})

    {:ok, _row} = Registry.update("hardcover", %{enabled: false})
    {:ok, _row} = Registry.update("hardcover", %{enabled: true})

    {:ok, entry} = Registry.fetch("hardcover")
    assert entry.config.api_token == "h.p.s"
    assert "hardcover" in Enum.map(Registry.enabled(level: :work), & &1.id)
  end

  test "a partial config update leaves fields it didn't mention alone" do
    {:ok, _row} =
      Registry.update("rreading_glasses", %{config: %{"base_url" => "http://rg.local:8788"}})

    {:ok, _row} = Registry.update("rreading_glasses", %{config: %{}})

    {:ok, entry} = Registry.fetch("rreading_glasses")
    assert entry.config.base_url == "http://rg.local:8788"
  end

  test "priority overrides reorder providers" do
    {:ok, _row} = Registry.update("audnexus", %{priority: -1})

    assert ["audnexus" | _rest] = Enum.map(Registry.all(), & &1.id)
  end
end
