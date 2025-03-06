defmodule Ambry.Books.PubSub.SeriesDeleted do
  @moduledoc false
  use Ambry.PubSub.MessageNew

  alias Ambry.Books.Series

  embedded_schema do
    field :id, :integer
    field :broadcast_topics, {:array, :string}
  end

  def new(%Series{} = series) do
    %__MODULE__{
      id: series.id,
      broadcast_topics: ["series-deleted:#{series.id}", "series-deleted:*"]
    }
  end

  @impl true
  def subscribe_topic, do: "series-deleted:*"
end
