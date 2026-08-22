defmodule AmbryWeb.Admin.WatchLive.New do
  @moduledoc """
  Finding an audiobook to watch.

  ## Every provider that can name a recording, side by side

  Results are grouped by the provider that gave them and nothing is ranked
  across providers. There is no primary source: a provider either can produce
  audio editions or it cannot, and the ones that can are all asked. What
  differs is shape — some answer with recordings, some answer with works that
  have to be opened — and shape is not standing.

  That matters most for exactly what this page is for, because providers are
  differently blind about the future and the past. A recording that is on
  preorder somewhere may be absent from a catalogue of what has been
  published; a recording from 1984 may be absent from a catalogue of what is
  for sale. Ranking one above the other would hide whichever half the operator
  happened to need.

  ## Only what has not come out yet

  Everything here is a recording that has not been published. A book whose
  audiobooks all came out years ago legitimately produces no candidates, and
  the page says *that* rather than "nothing found" — which would read as the
  provider not having it.

  ## Outcomes are shown even when they are empty

  A provider that was rate-limited and a provider that genuinely has nothing
  look identical in a list of results, and they mean opposite things. The
  per-provider outcome line says which happened.
  """

  use AmbryWeb, :admin_live_view

  alias Ambry.Metadata.Provider
  alias Ambry.Wanted
  alias Ambry.Wanted.Search

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       page_title: "Watch something",
       search_form: to_form(%{"title" => "", "author" => "", "narrator" => ""}, as: :search),
       candidates: [],
       outcomes: [],
       notes: [],
       searched: false,
       searching: false
     )}
  end

  @impl Phoenix.LiveView
  def handle_event("search", %{"search" => fields}, socket) do
    query = Provider.Query.from_fields(fields)

    if blank_query?(query) do
      {:noreply, put_flash(socket, :error, "Give it something to search for.")}
    else
      # The fan-out is several HTTP calls to providers that are sometimes
      # slow, so the page says it is working rather than appearing to have
      # ignored the click.
      send(self(), {:run_search, query})

      {:noreply,
       socket
       |> assign(searching: true, search_form: to_form(fields, as: :search))
       |> assign(candidates: [], outcomes: [], notes: [])}
    end
  end

  def handle_event("watch", %{"provider" => provider, "provider-id" => provider_id}, socket) do
    candidate =
      Enum.find(socket.assigns.candidates, fn candidate ->
        candidate.provider == provider and candidate.provider_id == provider_id
      end)

    {:noreply, add_watch(socket, candidate)}
  end

  @impl Phoenix.LiveView
  def handle_info({:run_search, query}, socket) do
    {candidates, outcomes, notes} = Search.candidates(query)

    {:noreply,
     assign(socket,
       candidates: candidates,
       outcomes: outcomes,
       notes: notes,
       searched: true,
       searching: false
     )}
  end

  defp add_watch(socket, nil),
    do: put_flash(socket, :error, "That result is no longer on screen.")

  defp add_watch(socket, candidate) do
    attrs = %{
      provider: candidate.provider,
      provider_id: candidate.provider_id,
      expected_release_date: candidate.published,
      edition: Map.from_struct(candidate.edition)
    }

    case Wanted.create_watch(attrs) do
      {:ok, watch} ->
        socket
        |> put_flash(:info, "Watching #{watch.edition.title}.")
        |> push_navigate(to: ~p"/admin/watches")

      # Already watching is not an error the operator has to fix; it is the
      # answer to what they asked for.
      {:error, :already_watching, watch} ->
        socket
        |> put_flash(:info, "Already watching #{watch.edition.title}.")
        |> push_navigate(to: ~p"/admin/watches")

      {:error, changeset} ->
        put_flash(socket, :error, "Couldn't watch that: #{errors(changeset)}")
    end
  end

  defp errors(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {message, _opts} -> message end)
    |> Enum.map_join("; ", fn {field, messages} -> "#{field} #{Enum.join(messages, ", ")}" end)
  end

  defp blank_query?(%Provider.Query{title: nil, author: nil, narrator: nil, keywords: nil}),
    do: true

  defp blank_query?(_query), do: false

  @doc "The candidates one provider returned, in the order it returned them."
  def by_provider(candidates) do
    candidates
    |> Enum.group_by(& &1.provider)
    |> Enum.sort_by(fn {provider, _} -> provider end)
  end

  @doc "What to call the provider a record came from."
  defdelegate provider_words(provider_id), to: Ambry.Wanted, as: :provider_name

  @doc """
  When a candidate is expected.

  Every candidate that reaches this page has a future date — the search drops
  anything already published, and anything undated — so there is no
  already-out case to render.
  """
  def date_words(date), do: Calendar.strftime(date, "%b %-d, %Y")

  @doc "How long the recording is, in words."
  defdelegate runtime(edition), to: Ambry.Wanted.Edition

  @doc false
  def credited(names), do: Enum.map(names, &%{name: &1})
end
