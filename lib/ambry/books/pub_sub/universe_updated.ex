defmodule Ambry.Books.PubSub.UniverseUpdated do
  @moduledoc false
  use Ambry.PubSub.Message

  alias Ambry.Books.Universe

  embedded_schema do
    field :id, :integer
    field :broadcast_topics, {:array, :string}
  end

  def new(%Universe{} = universe) do
    %__MODULE__{id: universe.id, broadcast_topics: [wildcard_topic()]}
  end

  def wildcard_topic, do: "universe-updated:*"
end
