defmodule Ambry.Wanted.RunRefresh do
  @moduledoc """
  Re-asks the providers when a watched recording is expected.

  **Not release detection.** Whether a date has passed is arithmetic and the
  list already does it. What only a provider can say is whether the date *is
  still the date*, and publishers move them constantly: a watch nagging on a
  date nobody believes teaches the operator to ignore the feature.

  **Only what is nearly due, and only rarely.** A watch six months out has
  nothing useful to say yet, so the window is the month ahead plus anything
  already past its date, that second half being where dates most often turn
  out to have moved.

  Nothing here settles a watch: a provider saying a recording came out is not
  the operator having it.
  """

  use Oban.Worker,
    queue: :metadata,
    max_attempts: 3

  import Ecto.Query

  alias Ambry.Metadata.Providers
  alias Ambry.Repo
  alias Ambry.Wanted.Edition
  alias Ambry.Wanted.Watch

  require Logger

  # Far enough ahead to catch a slip before the date arrives, near enough that
  # most watches are never asked about.
  @lookahead_days 31

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    today = Date.utc_today()
    watches = due_for_refresh(today)

    counts =
      Enum.reduce(watches, %{checked: 0, moved: 0, failed: 0}, fn watch, counts ->
        case refresh(watch) do
          {:moved, from, to} ->
            Logger.info("Watch #{watch.id} (#{watch.edition.title}) moved #{from} -> #{to}")

            %{counts | checked: counts.checked + 1, moved: counts.moved + 1}

          :unchanged ->
            %{counts | checked: counts.checked + 1}

          {:error, reason} ->
            Logger.warning("Watch #{watch.id} refresh failed: #{inspect(reason)}")
            %{counts | checked: counts.checked + 1, failed: counts.failed + 1}
        end
      end)

    if counts.moved > 0 or counts.failed > 0 do
      Logger.info("Watch refresh: #{inspect(counts)}")
    end

    {:ok, counts}
  end

  @doc """
  The watches worth asking about today. Undated ones are included: a watch
  with no date is waiting for one, and the provider is where it comes from.
  """
  def due_for_refresh(today \\ Date.utc_today()) do
    horizon = Date.add(today, @lookahead_days)

    Watch
    |> where([w], w.status == :upcoming)
    |> where([w], is_nil(w.expected_release_date) or w.expected_release_date <= ^horizon)
    |> Repo.all()
  end

  @doc """
  Re-reads one watch's record from the provider that supplied it.

  Answers `{:moved, from, to}`, `:unchanged`, or `{:error, reason}`. A
  provider that cannot be reached leaves the watch exactly as it was.
  """
  def refresh(%Watch{} = watch) do
    case fetch(watch) do
      {:ok, book} -> apply_refresh(watch, book)
      {:error, reason} -> {:error, reason}
    end
  end

  # `book_details` is the direct read: the operator already chose which record
  # this is, so there is nothing to search for and nothing to re-decide.
  defp fetch(%Watch{provider: provider, provider_id: provider_id}) do
    case Providers.book_details(provider, provider_id, refresh: true) do
      {:ok, book} -> {:ok, book}
      {:error, reason} -> {:error, reason}
    end
  end

  defp apply_refresh(watch, book) do
    date = published_date(book)
    edition = Edition.from_provider_book(book)

    attrs = %{expected_release_date: date}

    result =
      watch
      |> Ecto.Changeset.change()
      |> Ecto.Changeset.put_embed(:edition, refreshed_edition(watch.edition, edition))
      |> Ecto.Changeset.change(attrs)
      |> Repo.update()

    case result do
      {:ok, _updated} -> moved(watch.expected_release_date, date)
      {:error, changeset} -> {:error, changeset}
    end
  end

  # The refreshed record wins on facts that change, but a field the provider
  # has since dropped does not blank one already held: a thinner answer is a
  # worse answer, not a correction.
  defp refreshed_edition(%Edition{} = old, %Edition{} = new) do
    new
    |> Map.from_struct()
    |> Enum.reject(fn {_key, value} -> value in [nil, []] end)
    |> Map.new()
    |> then(&Map.merge(Map.from_struct(old), &1))
  end

  defp moved(same, same), do: :unchanged
  defp moved(from, to), do: {:moved, from, to}

  defp published_date(%{published: %{date: %Date{} = date}}), do: date
  defp published_date(_book), do: nil

  @doc "Queues a refresh now, for the operator who does not want to wait a week."
  def enqueue do
    %{}
    |> new()
    |> Oban.insert()
  end
end
