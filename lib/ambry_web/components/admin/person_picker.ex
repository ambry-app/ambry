defmodule AmbryWeb.Admin.PersonPicker do
  @moduledoc """
  Every photo and bio anything can find for one human, to pick from.

  ## Why every photo, not the best one

  The original picker showed one image per provider — each provider's top
  hit's primary photo. That is the right shape for "give me a face" and the
  wrong shape for the job: a profile photo has to survive a **circular crop**,
  and the obvious portrait is frequently the one that doesn't. A head at the
  edge of a wide shot, a red-carpet group photo, a book jacket with the face
  bottom-left — all fine as pictures, all unusable as an avatar. The
  alternative three rows down is often the one that works, and a one-per-
  provider grid can't offer it.

  So the candidates are rendered **in the circular frame they'll appear in**,
  at the size they'll appear at, with their dimensions. That's the whole
  decision, made by looking.

  ## Why several people

  Searching a name can return more than one human, and only the operator can
  tell which is theirs. Matches are grouped by person and captioned with
  whatever the provider offers as a disambiguator — TMDB's known-for credits
  earn their keep here.

  Bios come from the same fan-out and are picked separately: Wikipedia's lead
  paragraph, TMDB's biography and a book database's author blurb are three
  different texts about one person.

  ## The inbox does not use this

  The import form renders the same search inline, as ordinary decision rows —
  a photo is picked by *looking* and a bio by *reading*, and one modal holding
  both made each dismiss the other. This stays for the person form, where the
  page IS the person and there is nothing to sit beside.
  """

  use AmbryWeb, :live_component

  alias Ambry.Metadata.PersonSearch
  alias Ambry.Provenance
  alias Phoenix.LiveView.AsyncResult

  @impl Phoenix.LiveComponent
  def update(assigns, socket) do
    providers = PersonSearch.providers()
    query = assigns.query

    socket =
      socket
      |> assign(assigns)
      |> assign_new(:context, fn -> nil end)
      |> assign(
        providers: providers,
        matches: Map.new(providers, &{&1.id, AsyncResult.loading()})
      )

    {:ok,
     Enum.reduce(providers, socket, fn provider, socket ->
       start_async(socket, {:matches, provider.id}, fn ->
         PersonSearch.matches(provider, query)
       end)
     end)}
  end

  @impl Phoenix.LiveComponent
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-4xl space-y-6 p-6">
      <div>
        <h2 class="text-2xl font-bold">A photo for {@query}</h2>
        <p class="text-sm text-zinc-400">
          Shown in the circular frame they'll be displayed in — the biggest photo often isn't the
          one that survives the crop. Picking stages it as a URL import.
        </p>
      </div>

      <div :for={provider <- @providers} class="space-y-3">
        <% found = @matches[provider.id] %>

        <div :if={found.loading} class="flex items-center gap-3">
          <span class="text-sm font-semibold">{provider.display_name}</span>
          <span class="h-20 w-20 animate-pulse rounded-full bg-zinc-800" />
        </div>

        <div :if={!found.loading && found.result in [nil, []]} class="flex items-center gap-3">
          <span class="text-sm font-semibold">{provider.display_name}</span>
          <span class="text-sm text-zinc-500">nothing</span>
        </div>

        <div :for={match <- found.result || []} class="space-y-2">
          <div class="flex flex-wrap items-baseline gap-2">
            <span class="text-sm font-semibold">{provider.display_name}</span>
            <span class="text-sm">{match.name}</span>
            <span :if={match.note} class="truncate text-xs text-zinc-500">{match.note}</span>
          </div>

          <div :if={match.images != []} class="flex flex-wrap gap-3">
            <button
              :for={url <- match.images}
              type="button"
              phx-click="pick-image"
              phx-target={@myself}
              phx-value-url={url}
              phx-value-provider={match.provider_id}
              class="block"
              data-role="person-image"
            >
              <.image_with_size
                id={"pick-#{match.provider_id}-#{match.id}-#{:erlang.phash2(url)}"}
                src={proxied_remote_image_url(url)}
                class="h-24 w-24 cursor-pointer rounded-full object-cover object-top transition hover:ring-2 hover:ring-lime-500"
              />
            </button>
          </div>

          <div :if={match.description} class="flex items-start gap-3">
            <button
              type="button"
              phx-click="pick-bio"
              phx-target={@myself}
              phx-value-provider={match.provider_id}
              phx-value-index={match.id}
              class="flex-none rounded-sm border border-zinc-700 px-2 py-1 text-xs"
            >
              Use this bio
            </button>
            <p class="line-clamp-3 text-xs text-zinc-400">
              {match.description}
            </p>
          </div>
        </div>
      </div>

      <div class="space-y-1 border-t border-zinc-800 pt-4 text-sm">
        <p class="font-semibold">Search the web instead:</p>
        <div class="flex gap-4">
          <a
            href={"https://www.google.com/search?tbm=isch&q=#{URI.encode_www_form(@query)}"}
            target="_blank"
            rel="noopener"
            class="text-brand-dark hover:underline"
          >
            Google Images
          </a>
          <a
            href={"https://duckduckgo.com/?ia=images&iax=images&q=#{URI.encode_www_form(@query)}"}
            target="_blank"
            rel="noopener"
            class="text-brand-dark hover:underline"
          >
            DuckDuckGo Images
          </a>
        </div>
        <p class="text-xs text-zinc-500">
          Then paste the image URL in — or copy the image itself and paste it onto the upload area.
        </p>
      </div>
    </div>
    """
  end

  @impl Phoenix.LiveComponent
  def handle_async({:matches, provider_id}, {:ok, matches}, socket) do
    {:noreply, put_matches(socket, provider_id, matches)}
  end

  # A provider blowing up just means an empty column.
  def handle_async({:matches, provider_id}, {:exit, _reason}, socket) do
    {:noreply, put_matches(socket, provider_id, [])}
  end

  defp put_matches(socket, provider_id, matches) do
    assign(
      socket,
      matches: Map.update!(socket.assigns.matches, provider_id, &AsyncResult.ok(&1, matches))
    )
  end

  @impl Phoenix.LiveComponent
  def handle_event("pick-image", %{"url" => url, "provider" => provider}, socket) do
    send(self(), {:person_image_picked, socket.assigns.context, url, source(provider)})
    {:noreply, socket}
  end

  def handle_event("pick-bio", %{"provider" => provider, "index" => id}, socket) do
    case find_match(socket, provider, id) do
      nil ->
        {:noreply, socket}

      match ->
        send(
          self(),
          {:person_bio_picked, socket.assigns.context, match.description, source(provider)}
        )

        {:noreply, socket}
    end
  end

  defp find_match(socket, provider_id, id) do
    case socket.assigns.matches[provider_id] do
      %AsyncResult{result: matches} when is_list(matches) -> Enum.find(matches, &(&1.id == id))
      _not_loaded -> nil
    end
  end

  defp source(provider_id), do: Provenance.provider_source(provider_id)
end
