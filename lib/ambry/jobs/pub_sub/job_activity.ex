defmodule Ambry.Jobs.PubSub.JobActivity do
  @moduledoc false
  use Ambry.PubSub.Message

  embedded_schema do
    field :event, Ecto.Enum, values: [:start, :stop, :exception]
    field :queue, :string
    field :broadcast_topics, {:array, :string}
  end

  def new(event, queue) do
    %__MODULE__{event: event, queue: queue, broadcast_topics: [topic()]}
  end

  @doc """
  One topic for all of it.

  Nobody listening cares which job moved — the only question anyone asks is
  "has the picture changed", and the answer is followed by re-reading the
  counts. A topic per queue would make every subscriber join five of them to
  learn the same thing.
  """
  def topic, do: "job-activity"
end
