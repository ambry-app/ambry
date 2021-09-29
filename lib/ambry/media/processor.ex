defmodule Ambry.Media.Processor do
  use Oban.Worker, queue: :media

  alias Ambry.Media
  alias Ambry.Media.Processor.MP3Concat

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"media_id" => id}}) do
    media = Media.get_media!(id)

    cond do
      MP3Concat.can_run?(media) -> MP3Concat.run(media)
      true -> raise "no matching processor found"
    end
  end
end
