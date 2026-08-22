defmodule Ambry.Wanted do
  @moduledoc """
  Audiobooks that don't exist yet.

  Everything else in Ambry describes what the library *holds*. This describes
  what it is waiting for — which is the one thing the library cannot represent
  on its own, and the one thing an operator forgets.

  ## What a watch is for

  Not a wishlist. A watch exists to become **due**: the expected date arrives,
  the admin dashboard starts nagging, and it keeps nagging until the operator
  either has the recording or says otherwise. A watch that never becomes due
  and is never dismissed has failed to do its job.

  Which is why `due?/1` says only that a date has passed, never that a book
  exists. A provider's date is a plan; the recording turning up is a fact, and
  the two are told apart everywhere in this context.

  ## Requests, later

  A user-facing request is the same idea with an owner attached, and it will
  get its own table rather than a `user_id` here: a watch is about the
  recording, so two people waiting for the same book is still one watch.
  `Ambry.Wanted.Edition` is deliberately shared between them, so promotion
  from a watch to a request is a copy rather than a translation.
  """

  use Boundary,
    deps: [Ambry, Ambry.Media],
    exports: [Watch, {Edition, []}, {Search, []}]

  import Ecto.Query

  alias Ambry.Metadata.Registry
  alias Ambry.Repo
  alias Ambry.Wanted.Watch

  @doc """
  Every watch, loudest first.

  Ordering is by *who is waiting on whom*, matching the admin dashboard: what
  is due comes first because it needs a human, then what is still coming in
  date order, then what has been settled. A watch with no date sorts after
  the dated ones — it is a real state, but it is not a deadline.
  """
  def list_watches(opts \\ []) do
    today = Keyword.get(opts, :today, Date.utc_today())

    Watch
    |> maybe_filter_status(Keyword.get(opts, :status))
    |> Repo.all()
    |> Repo.preload(:media)
    |> Enum.sort_by(&sort_key(&1, today))
  end

  defp maybe_filter_status(query, nil), do: query
  defp maybe_filter_status(query, status), do: where(query, [w], w.status == ^status)

  defp sort_key(watch, today) do
    {status_rank(watch, today), date_rank(watch), watch.edition.title || ""}
  end

  defp status_rank(watch, today) do
    cond do
      Watch.due?(watch, today) -> 0
      watch.status == :upcoming -> 1
      watch.status == :released -> 2
      true -> 3
    end
  end

  # `:infinity` would not compare against a Date. A far-future sentinel keeps
  # undated watches last without special-casing the comparison.
  defp date_rank(%Watch{expected_release_date: nil}), do: ~D[9999-12-31]
  defp date_rank(%Watch{expected_release_date: date}), do: date

  @doc "The watches whose expected date has arrived and that nobody has settled."
  def list_due(today \\ Date.utc_today()) do
    Watch
    |> where([w], w.status == :upcoming)
    |> where([w], not is_nil(w.expected_release_date))
    |> where([w], w.expected_release_date <= ^today)
    |> order_by([w], asc: w.expected_release_date)
    |> Repo.all()
  end

  @doc """
  What the dashboard needs to decide whether to nag, in one query pair.

  `due` is the nag. `next` is what makes the card worth reading when there is
  nothing to nag about — "nothing out yet, next is Blightfall on Sep 1" is an
  answer; an empty card is not.
  """
  def summary(today \\ Date.utc_today()) do
    due = list_due(today)

    next =
      Watch
      |> where([w], w.status == :upcoming)
      |> where([w], not is_nil(w.expected_release_date))
      |> where([w], w.expected_release_date > ^today)
      |> order_by([w], asc: w.expected_release_date)
      |> limit(1)
      |> Repo.one()

    %{
      due: due,
      due_count: length(due),
      next: next,
      upcoming_count: Repo.aggregate(where(Watch, [w], w.status == :upcoming), :count)
    }
  end

  @doc "Fetches a watch, raising when it isn't there."
  def get_watch!(id), do: Watch |> Repo.get!(id) |> Repo.preload(:media)

  @doc "The watch for a provider's recording, if one exists."
  def get_by_provider(provider, provider_id) do
    Repo.get_by(Watch, provider: to_string(provider), provider_id: to_string(provider_id))
  end

  @doc """
  Starts watching a recording.

  Answers `{:error, :already_watching, watch}` rather than a changeset error
  when the recording is already watched, because the useful response to "add
  this" is the watch that already exists, not a form telling the operator off.
  """
  def create_watch(attrs) do
    provider = attrs[:provider] || attrs["provider"]
    provider_id = attrs[:provider_id] || attrs["provider_id"]

    case get_by_provider(provider, provider_id) do
      nil ->
        %Watch{}
        |> Watch.changeset(attrs)
        |> Repo.insert()

      existing ->
        {:error, :already_watching, existing}
    end
  end

  @doc "Changes what the operator can change: the date, the state, the note."
  def update_watch(%Watch{} = watch, attrs) do
    watch
    |> Watch.edit_changeset(attrs)
    |> Repo.update()
  end

  @doc "A changeset for the edit form."
  def change_watch(%Watch{} = watch, attrs \\ %{}), do: Watch.edit_changeset(watch, attrs)

  @doc """
  Marks a watch satisfied.

  `media` is optional because the operator can know a book is out before it is
  in the library — and a watch that stays `upcoming` because the import hasn't
  happened yet would keep nagging about something already handled.
  """
  def mark_released(%Watch{} = watch, media \\ nil) do
    update_watch(watch, %{status: :released, media_id: media && media.id})
  end

  @doc "Stops the nagging without claiming the recording arrived."
  def dismiss(%Watch{} = watch), do: update_watch(watch, %{status: :dismissed})

  @doc "Puts a dismissed or released watch back into waiting."
  def reopen(%Watch{} = watch), do: update_watch(watch, %{status: :upcoming})

  @doc """
  What to call the provider a watch's record came from.

  Read off the registry rather than listed here: a provider added later should
  name itself, and a hardcoded list would quietly start showing raw ids. Falls
  back to the id for a provider that has since been removed, because a watch
  outlives the provider that supplied it.
  """
  def provider_name(provider_id) do
    case Registry.fetch(provider_id) do
      {:ok, entry} -> entry.display_name
      {:error, _reason} -> provider_id
    end
  end

  @doc "Forgets a watch entirely. Prefer `dismiss/1` — see `Watch`."
  def delete_watch(%Watch{} = watch), do: Repo.delete(watch)
end
