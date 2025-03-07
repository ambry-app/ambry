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
      broadcast_topics: [person_topic(person), wildcard_topic()]
    }
  end

  def wildcard_topic, do: "person-updated:*"

  def person_topic(%Person{} = person), do: "person-updated:#{person.id}"
end
