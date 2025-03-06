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

  def perform(%Oban.Job{args: %{"person_id" => person_id, "image_path" => image_path}}) do
    Ambry.People.update_person_thumbnails!(person_id, image_path)
  end
end
