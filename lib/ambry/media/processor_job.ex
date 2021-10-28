defmodule Ambry.Media.ProcessorJob do
  @moduledoc """
  Media uploads processor Oban job.
  """

  use Oban.Worker,
    queue: :media,
    max_attempts: 1

  alias Ambry.Media
  alias Ambry.Media.Processor

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"media_id" => id}}) do
    media = Media.get_media!(id)
    Processor.run!(media)
  end
end
