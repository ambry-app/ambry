defmodule Ambry.People.PubSub.PersonDeleted do
  @moduledoc false
  use Ambry.PubSub.MessageNew

  alias Ambry.People.Person

  embedded_schema do
    field :id, :integer
    field :broadcast_topics, {:array, :string}
  end

  def new(%Person{} = person) do
    %__MODULE__{
      id: person.id,
      broadcast_topics: ["person-deleted:#{person.id}", "person-deleted:*"]
    }
  end

  @impl true
  def subscribe_topic, do: "person-deleted:*"
end
