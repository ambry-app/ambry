defmodule Ambry.Media.Processor do
  @moduledoc """
  Media uploads processor Oban job.

  Delegates to other modules depending on what kind of files were uploaded.
  """

  use Oban.Worker,
    queue: :media,
    max_attempts: 1

  alias Ambry.Media
  alias Ambry.Media.Processor.{MP3, MP3Concat, MP4, MP4Concat}

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"media_id" => id}}) do
    media = Media.get_media!(id)

    {:ok, media} = Media.update_media(media, %{status: :processing})

    try do
      run_processor!(media)
    rescue
      exception ->
        {:ok, _media} = Media.update_media(media, %{status: :error})

        reraise exception, __STACKTRACE__
    end
  end

  defp run_processor!(media) do
    cond do
      MP3Concat.can_run?(media) -> MP3Concat.run(media)
      MP3.can_run?(media) -> MP3.run(media)
      MP4Concat.can_run?(media) -> MP4Concat.run(media)
      MP4.can_run?(media) -> MP4.run(media)
      true -> raise "no matching processor found"
    end
  end
end
