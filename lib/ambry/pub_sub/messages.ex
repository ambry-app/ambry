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

defmodule Ambry.PubSub.BookCreated do
  @moduledoc false
  use Ambry.PubSub.MessageNew

  alias Ambry.Books.Book

  embedded_schema do
    field :id, :integer
    field :broadcast_topics, {:array, :string}
  end

  def new(%Book{} = book) do
    %__MODULE__{id: book.id, broadcast_topics: ["book-created:*"]}
  end

  @impl true
  def subscribe_topic, do: "book-created:*"
end

defmodule Ambry.PubSub.BookUpdated do
  @moduledoc false
  use Ambry.PubSub.MessageNew

  alias Ambry.Books.Book

  embedded_schema do
    field :id, :integer
    field :broadcast_topics, {:array, :string}
  end

  def new(%Book{} = book) do
    %__MODULE__{
      id: book.id,
      broadcast_topics: ["book-updated:#{book.id}", "book-updated:*"]
    }
  end

  @impl true
  def subscribe_topic, do: "book-updated:*"
end

defmodule Ambry.PubSub.BookDeleted do
  @moduledoc false
  use Ambry.PubSub.MessageNew

  alias Ambry.Books.Book

  embedded_schema do
    field :id, :integer
    field :broadcast_topics, {:array, :string}
  end

  def new(%Book{} = book) do
    %__MODULE__{
      id: book.id,
      broadcast_topics: ["book-deleted:#{book.id}", "book-deleted:*"]
    }
  end

  @impl true
  def subscribe_topic, do: "book-deleted:*"
end

defmodule Ambry.PubSub.SeriesCreated do
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

defmodule Ambry.PubSub.SeriesUpdated do
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
      broadcast_topics: ["series-updated:#{series.id}", "series-updated:*"]
    }
  end

  @impl true
  def subscribe_topic, do: "series-updated:*"
end

defmodule Ambry.PubSub.SeriesDeleted do
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
