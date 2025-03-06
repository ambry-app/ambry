defmodule Ambry.Books.PubSub.SeriesCreated do
  @moduledoc false
  use Ambry.PubSub.MessageNew

  alias Ambry.Books.Series

  embedded_schema do
    field :id, :integer
    field :broadcast_topics, {:array, :string}
  end

  def new(%Series{} = series) do
    %__MODULE__{id: series.id, broadcast_topics: ["series-created:*"]}
  end

  @impl true
  def subscribe_topic, do: "series-created:*"
end
