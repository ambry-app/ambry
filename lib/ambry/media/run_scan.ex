defmodule Ambry.Media.RunScan do
  @moduledoc """
  Direct-play media scan Oban job.
  """

  use Oban.Worker,
    queue: :media,
    max_attempts: 1

  alias Ambry.Media
  alias Ambry.Media.Scanner

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"media_id" => id}}) do
    media = Media.get_media!(id)

    case Scanner.scan(media) do
      {:ok, _media} = success ->
        success

      {:error, reason} = error ->
        Logger.warning(fn -> "Scan failed for media #{id}: #{inspect(reason)}" end)
        error
    end
  end
end
