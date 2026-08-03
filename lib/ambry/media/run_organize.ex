defmodule Ambry.Media.RunOrganize do
  @moduledoc """
  Brings managed files back in line with the naming template.

  Three shapes of job, all idempotent — a recording already in the right
  place is a no-op, which is what almost every run finds:

    * `%{"media_id" => id}` — after that recording was edited;
    * `%{"book_id" => id}` — after a book was edited, since its title,
      authors and series appear in the path of every recording of it;
    * `%{}` — the whole library, for the nightly sweep and for the one thing
      no edit-time trigger can see: a change to the template itself.
  """

  use Oban.Worker,
    queue: :media,
    max_attempts: 3

  alias Ambry.Media.Organization
  alias Ambry.Repo

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"media_id" => media_id}}) do
    case Repo.get(Ambry.Media.Media, media_id) do
      nil -> :ok
      media -> log(Organization.organize(media), media_id)
    end
  end

  def perform(%Oban.Job{args: %{"book_id" => book_id}}) do
    for media <- Organization.book_media(book_id), do: log(Organization.organize(media), media.id)
    :ok
  end

  def perform(%Oban.Job{}) do
    {:ok, counts} = Organization.organize_all()

    if counts.moved > 0 or counts.failed > 0,
      do: Logger.info(fn -> "Organize: #{inspect(counts)}" end)

    :ok
  end

  # A recording that can't be moved — most likely because something is
  # already at its new path — must not fail the job and retry forever. The
  # operator has to resolve the collision; the queue can't.
  defp log({:ok, _moved_or_noop}, _media_id), do: :ok

  defp log({:error, reason}, media_id) do
    Logger.warning(fn -> "Couldn't organize media #{media_id}: #{inspect(reason)}" end)
    :ok
  end
end
