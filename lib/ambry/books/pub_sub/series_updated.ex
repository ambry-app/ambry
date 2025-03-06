defmodule Ambry.Books.PubSub.SeriesUpdated do
  @moduledoc false
  use Ambry.PubSub.Message

  alias Ambry.Books.Series

  embedded_schema do
    field :id, :integer
    field :broadcast_topics, {:array, :string}
  end

  def new(%Series{} = series) do
    %__MODULE__{
      id: series.id,
      broadcast_topics: ["series-updated:#{series.id}", "series-updated:*"]
    }
  end

  @impl true
  def subscribe_topic, do: "series-updated:*"
end
