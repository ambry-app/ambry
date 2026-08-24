defmodule Ambry.Wanted do
  @moduledoc """
  Audiobooks that don't exist yet.

  Everything else in Ambry describes what the library holds. This describes
  what it is waiting for.

  Not a wishlist: a watch exists to become **due**, so the expected date
  arrives, the dashboard starts nagging, and it keeps nagging until the
  operator either has the recording or says otherwise.

  Which is why `due?/1` says only that a date has passed, never that a book
  exists. A provider's date is a plan; the recording turning up is a fact.

  A user-facing request is the same idea with an owner attached, and will get
  its own table rather than a `user_id` here: a watch is about the recording,
  so two people waiting for one book is still one watch.
  `Ambry.Wanted.Edition` is deliberately shared between them.
  """

  use Boundary,
    deps: [Ambry, Ambry.Media],
    exports: [Watch, {Edition, []}, {Search, []}]

  import Ecto.Query

  alias Ambry.Metadata.Registry
  alias Ambry.Repo
  alias Ambry.Wanted.Watch

  @doc """
  Every watch, loudest first: what is still coming, soonest first, then what
  has been settled. A watch with no date sorts after the dated ones.

  Due watches need no rank of their own -- due is an upcoming watch whose date
  has passed, so ordering the upcoming ones by date floats them to the top.

  Ordered in SQL, not by `Enum.sort_by/2`: a `Date` inside a sort-key tuple is
  compared in Erlang term order, which ranks the struct's `day` above its
  `year`. The title tiebreaker only settles watches sharing a status and a
  date, so the list is stable between reloads.
  """
  def list_watches(opts \\ []) do
    Watch
    |> maybe_filter_status(Keyword.get(opts, :status))
    |> order_by([w],
      asc: fragment("CASE ? WHEN 'upcoming' THEN 0 WHEN 'released' THEN 1 ELSE 2 END", w.status),
      asc_nulls_last: w.expected_release_date,
      asc: fragment("? ->> 'title'", w.edition)
    )
    |> Repo.all()
    |> Repo.preload(:media)
  end

  defp maybe_filter_status(query, nil), do: query
  defp maybe_filter_status(query, status), do: where(query, [w], w.status == ^status)

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
  nothing to nag about.
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

  Answers `{:error, :already_watching, watch}` rather than a changeset error,
  because the useful response to "add this" is the watch that already
  exists.
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

  `media` is optional because the operator can know a book is out before it
  is in the library.
  """
  def mark_released(%Watch{} = watch, media \\ nil) do
    watch
    |> Watch.settle_changeset(%{status: :released, media_id: media && media.id})
    |> Repo.update()
  end

  @doc "Stops the nagging without claiming the recording arrived."
  def dismiss(%Watch{} = watch), do: update_watch(watch, %{status: :dismissed})

  @doc "Puts a dismissed or released watch back into waiting."
  def reopen(%Watch{} = watch), do: update_watch(watch, %{status: :upcoming})

  @doc """
  The provider records the operator is waiting for, as `{provider, id}`.

  A set, because the caller asks the same question of every candidate in a
  ranked list. Only watches still being waited on.
  """
  def open_refs do
    Watch
    |> where([w], w.status == :upcoming)
    |> select([w], {w.provider, w.provider_id})
    |> Repo.all()
    |> MapSet.new()
  end

  @doc """
  Settles the watches an import answered, and says which.

  Keyed on the provider records the operator adopted, not on what the matcher
  merely proposed: a candidate offered and passed over is no evidence.
  Returns the watches it settled so the caller can say so.

  Never raises and never fails the caller. This runs after the recording is
  already in the library, where a raised error would report a successful
  import as a failed one.
  """
  def settle(refs, media) do
    refs = MapSet.new(refs)

    Watch
    |> where([w], w.status == :upcoming)
    |> Repo.all()
    |> Enum.filter(&MapSet.member?(refs, {&1.provider, &1.provider_id}))
    |> Enum.flat_map(fn watch ->
      case mark_released(watch, media) do
        {:ok, settled} -> [settled]
        {:error, _changeset} -> []
      end
    end)
  end

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
