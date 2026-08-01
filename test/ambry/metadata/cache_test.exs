defmodule Ambry.Metadata.CacheTest do
  use Ambry.DataCase

  alias Ambry.Metadata.Cache

  test "caches the result of a successful fetch" do
    assert {:ok, :value} = Cache.fetch("test:op:arg", fn -> {:ok, :value} end)

    assert {:ok, :value} =
             Cache.fetch("test:op:arg", fn -> raise "fetch_fun should not be called" end)
  end

  test "does not cache errors" do
    assert {:error, :boom} = Cache.fetch("test:op:arg", fn -> {:error, :boom} end)
    assert {:ok, :value} = Cache.fetch("test:op:arg", fn -> {:ok, :value} end)
  end

  test "expired entries are re-fetched" do
    assert {:ok, :old} = Cache.fetch("test:op:arg", fn -> {:ok, :old} end)
    assert {:ok, :new} = Cache.fetch("test:op:arg", fn -> {:ok, :new} end, ttl: -1)
  end

  test "serves stale value when re-fetch fails" do
    assert {:ok, :old} = Cache.fetch("test:op:arg", fn -> {:ok, :old} end)
    assert {:ok, :old} = Cache.fetch("test:op:arg", fn -> {:error, :down} end, ttl: -1)
  end

  test "refresh bypasses a fresh cache entry" do
    assert {:ok, :old} = Cache.fetch("test:op:arg", fn -> {:ok, :old} end)
    assert {:ok, :new} = Cache.fetch("test:op:arg", fn -> {:ok, :new} end, refresh: true)
    assert {:ok, :new} = Cache.fetch("test:op:arg", fn -> {:ok, :unused} end)
  end

  test "refresh serves stale on fetch failure" do
    assert {:ok, :old} = Cache.fetch("test:op:arg", fn -> {:ok, :old} end)
    assert {:ok, :old} = Cache.fetch("test:op:arg", fn -> {:error, :down} end, refresh: true)
  end

  test "clear_provider/1 removes only that provider's entries" do
    assert {:ok, :a} = Cache.fetch("prov_a:op:arg", fn -> {:ok, :a} end)
    assert {:ok, :b} = Cache.fetch("prov_b:op:arg", fn -> {:ok, :b} end)

    Cache.clear_provider("prov_a")

    assert {:ok, :fresh} = Cache.fetch("prov_a:op:arg", fn -> {:ok, :fresh} end)
    assert {:ok, :b} = Cache.fetch("prov_b:op:arg", fn -> raise "should be cached" end)
  end
end
