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
      broadcast_topics: [series_topic(series), wildcard_topic()]
    }
  end

  def wildcard_topic, do: "series-updated:*"

  def series_topic(%Series{} = series), do: "series-updated:#{series.id}"
end
