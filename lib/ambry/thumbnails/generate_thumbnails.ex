defmodule Ambry.Thumbnails.GenerateThumbnails do
  @moduledoc """
  Generates various thumbnails for media and person images.
  """

  use Oban.Worker,
    queue: :images,
    max_attempts: 1

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"media_id" => id}}) do
    id
    |> Ambry.Media.get_media!()
    |> Ambry.Media.generate_thumbnails!()
  end

  def perform(%Oban.Job{args: %{"person_id" => id}}) do
    id
    |> Ambry.People.get_person!()
    |> Ambry.People.generate_thumbnails!()
  end
end
