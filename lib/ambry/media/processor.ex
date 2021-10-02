defmodule Ambry.Media.Processor do
  @moduledoc """
  Media uploads processor Oban job.

  Delegates to other modules depending on what kind of files were uploaded.
  """

  use Oban.Worker, queue: :media

  alias Ambry.Media
  alias Ambry.Media.Processor.{MP3, MP3Concat}

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"media_id" => id}}) do
    media = Media.get_media!(id)

    cond do
      MP3Concat.can_run?(media) -> MP3Concat.run(media)
      MP3.can_run?(media) -> MP3.run(media)
      true -> raise "no matching processor found"
    end
  end
end
