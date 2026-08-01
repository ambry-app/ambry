defmodule Ambry.Metadata.ProvidersTest do
  use Ambry.DataCase, async: false
  use Patch

  alias Ambry.Metadata.Provider
  alias Ambry.Metadata.Providers
  alias Ambry.Metadata.Registry

  test "routes to the provider module and caches the normalized result" do
    book = %Provider.Book{provider: "rreading_glasses", id: "1", title: "A Book"}

    patch(Ambry.Metadata.Providers.RreadingGlasses, :search_books, fn "carl", _config ->
      {:ok, [book]}
    end)

    assert {:ok, [^book]} = Providers.search_books("rreading_glasses", "carl")

    # cached now: the provider module is no longer consulted
    restore(Ambry.Metadata.Providers.RreadingGlasses)
    assert {:ok, [^book]} = Providers.search_books("rreading_glasses", "carl")
  end

  test "refresh: true re-fetches through the provider" do
    patch(Ambry.Metadata.Providers.RreadingGlasses, :search_books, fn _query, _config ->
      {:ok, []}
    end)

    assert {:ok, []} = Providers.search_books("rreading_glasses", "carl")

    book = %Provider.Book{provider: "rreading_glasses", id: "2", title: "Fresh"}

    patch(Ambry.Metadata.Providers.RreadingGlasses, :search_books, fn _query, _config ->
      {:ok, [book]}
    end)

    assert {:ok, [^book]} = Providers.search_books("rreading_glasses", "carl", refresh: true)
  end

  test "unknown providers are rejected" do
    assert {:error, :unknown_provider} = Providers.search_books("nope", "q")
  end

  test "disabled providers are rejected" do
    {:ok, _row} = Registry.update("audible", %{enabled: false})

    assert {:error, :provider_disabled} = Providers.search_books("audible", "q")
  end

  test "capabilities are enforced" do
    assert {:error, :unsupported_capability} = Providers.chapters("rreading_glasses", "B08")
    assert {:error, :unsupported_capability} = Providers.search_books("audnexus", "q")
  end
end
