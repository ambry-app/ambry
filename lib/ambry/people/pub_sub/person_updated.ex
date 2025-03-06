defmodule Ambry.People.PubSub.PersonUpdated do
  @moduledoc false
  use Ambry.PubSub.Message

  alias Ambry.People.Person

  embedded_schema do
    field :id, :integer
    field :broadcast_topics, {:array, :string}
  end

  def new(%Person{} = person) do
    %__MODULE__{
      id: person.id,
      broadcast_topics: ["person-updated:#{person.id}", "person-updated:*"]
    }
  end

  @impl true
  def subscribe_topic, do: "person-updated:*"
end
