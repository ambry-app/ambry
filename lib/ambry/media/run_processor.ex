defmodule Ambry.Media.RunProcessor do
  @moduledoc """
  Media uploads processor Oban job.
  """

  use Oban.Worker,
    queue: :media,
    max_attempts: 1

  alias Ambry.Media
  alias Ambry.Media.Processor

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"media_id" => id, "processor" => processor_string}}) do
    processor = String.to_existing_atom(processor_string)
    media = Media.get_media!(id)
    Processor.run!(media, processor)
  end
end
