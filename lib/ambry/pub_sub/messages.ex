defmodule Ambry.PubSub.PersonCreated do
  @moduledoc false
  use Ambry.PubSub.MessageNew

  alias Ambry.People.Person

  embedded_schema do
    field :id, :integer
    field :broadcast_topics, {:array, :string}
  end

  def new(%Person{} = person) do
    %__MODULE__{id: person.id, broadcast_topics: ["person-created:*"]}
  end

  @impl true
  def subscribe_topic, do: "person-created:*"
end

defmodule Ambry.PubSub.PersonUpdated do
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
      broadcast_topics: ["person-updated:#{person.id}", "person-updated:*"]
    }
  end

  @impl true
  def subscribe_topic, do: "person-updated:*"
end

defmodule Ambry.PubSub.PersonDeleted do
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
