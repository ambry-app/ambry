defmodule Ambry.Search.IndexManager do
  @moduledoc """
  GenServer to manage search index records and keep them up-to-date as media,
  authors and series are added, updated or deleted.
  """

  use GenServer

  alias Ambry.PubSub

  alias Ambry.Search.Index

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [])
  end

  @impl GenServer
  def init(_opts) do
    :ok = PubSub.subscribe("book:*")
    :ok = PubSub.subscribe("media:*")
    :ok = PubSub.subscribe("person:*")
    :ok = PubSub.subscribe("series:*")

    {:ok, nil}
  end

  @impl GenServer
  def handle_info(%PubSub.Message{action: :created} = message, state) do
    %{type: type, id: id} = message

    :ok = Index.insert(type, id)

    {:noreply, state}
  end

  def handle_info(%PubSub.Message{action: :updated} = message, state) do
    %{type: type, id: id} = message

    :ok = Index.update(type, id)

    {:noreply, state}
  end

  def handle_info(%PubSub.Message{action: :deleted} = message, state) do
    %{type: type, id: id} = message

    :ok = Index.delete(type, id)

    {:noreply, state}
  end
end
