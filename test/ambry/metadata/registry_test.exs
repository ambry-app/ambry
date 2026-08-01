defmodule Ambry.Metadata.RegistryTest do
  use Ambry.DataCase

  alias Ambry.Metadata.Registry

  test "all/0 returns every known provider enabled by default, in priority order" do
    entries = Registry.all()

    assert Enum.map(entries, & &1.id) == ["rreading_glasses", "hardcover", "audible", "audnexus"]
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

    assert ["rreading_glasses", "audnexus"] =
             Enum.map(Registry.enabled(capability: :author_search), & &1.id)
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

  test "fetch/1 returns an error for unknown providers" do
    assert {:error, :unknown_provider} = Registry.fetch("goodreads")
  end

  test "priority overrides reorder providers" do
    {:ok, _row} = Registry.update("audnexus", %{priority: -1})

    assert ["audnexus" | _rest] = Enum.map(Registry.all(), & &1.id)
  end
end
