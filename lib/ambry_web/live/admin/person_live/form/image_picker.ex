defmodule AmbryWeb.Admin.PersonLive.Form.ImagePicker do
  @moduledoc """
  Aggregated profile-image picker for the person form.

  Searches every enabled author-search provider for the person's name in
  parallel and collects each provider's best-match photo into a one-click
  grid; picking a candidate stages it as a URL import in the parent form,
  with that provider recorded as the image's provenance source. External
  image-search links cover the genuinely obscure — manual-but-assisted is
  the accepted floor.
  """
  use AmbryWeb, :live_component

  alias Ambry.Metadata.Providers
  alias Ambry.Metadata.Registry
  alias Ambry.Provenance
  alias Phoenix.LiveView.AsyncResult

  @impl Phoenix.LiveComponent
  def update(assigns, socket) do
    providers = Registry.enabled(capability: :author_search)
    query = assigns.query

    socket =
      socket
      |> assign(assigns)
      |> assign(
        providers: providers,
        candidates: Map.new(providers, &{&1.id, AsyncResult.loading()})
      )

    {:ok,
     Enum.reduce(providers, socket, fn provider, socket ->
       start_async(socket, {:candidate, provider.id}, fn -> find_candidate(provider, query) end)
     end)}
  end

  @impl Phoenix.LiveComponent
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-3xl space-y-4 p-6">
      <h2 class="text-2xl font-bold">Find images</h2>
      <p class="text-sm text-zinc-600 dark:text-zinc-400">
        Best match for “{@query}” from every enabled provider. Pick a photo to stage it as a URL
        import — it uploads when you save.
      </p>

      <div class="flex flex-wrap gap-4">
        <div :for={provider <- @providers} class="w-40 space-y-1">
          <div class="text-sm font-semibold">{provider.display_name}</div>
          <% candidate = @candidates[provider.id] %>
          <%= cond do %>
            <% candidate.loading -> %>
              <div class="h-40 w-40 animate-pulse rounded-sm bg-zinc-200 dark:bg-zinc-800" />
            <% is_nil(candidate.result) -> %>
              <div class="flex h-40 w-40 items-center justify-center rounded-sm bg-zinc-100 text-sm text-zinc-500 dark:bg-zinc-900">
                No match
              </div>
            <% true -> %>
              <button
                type="button"
                class="block"
                phx-click="pick"
                phx-target={@myself}
                phx-value-url={candidate.result.image_url}
                phx-value-source={Provenance.provider_source(provider.id)}
              >
                <img
                  src={proxied_remote_image_url(candidate.result.image_url)}
                  alt={candidate.result.name}
                  class="h-40 w-40 cursor-pointer rounded-sm object-cover object-top transition hover:ring-2 hover:ring-lime-500"
                />
              </button>
              <div class="truncate text-xs text-zinc-500" title={candidate.result.name}>
                {candidate.result.name}
              </div>
          <% end %>
        </div>
      </div>

      <div class="space-y-1 border-t border-zinc-200 pt-4 text-sm dark:border-zinc-800">
        <p class="font-semibold">Search the web instead:</p>
        <div class="flex gap-4">
          <a
            href={"https://www.google.com/search?tbm=isch&q=#{URI.encode_www_form(@query)}"}
            target="_blank"
            rel="noopener"
            class="text-brand hover:underline dark:text-brand-dark"
          >
            Google Images
          </a>
          <a
            href={"https://duckduckgo.com/?ia=images&iax=images&q=#{URI.encode_www_form(@query)}"}
            target="_blank"
            rel="noopener"
            class="text-brand hover:underline dark:text-brand-dark"
          >
            DuckDuckGo Images
          </a>
        </div>
        <p class="text-xs text-zinc-500">
          Then paste the image URL into “Import image from URL” — or copy the image itself and
          paste it straight onto the upload area.
        </p>
      </div>
    </div>
    """
  end

  @impl Phoenix.LiveComponent
  def handle_async({:candidate, provider_id}, {:ok, candidate}, socket) do
    {:noreply, put_candidate(socket, provider_id, candidate)}
  end

  # a provider blowing up just means no candidate from it
  def handle_async({:candidate, provider_id}, {:exit, _reason}, socket) do
    {:noreply, put_candidate(socket, provider_id, nil)}
  end

  defp put_candidate(socket, provider_id, candidate) do
    candidates =
      Map.update!(socket.assigns.candidates, provider_id, &AsyncResult.ok(&1, candidate))

    assign(socket, candidates: candidates)
  end

  @impl Phoenix.LiveComponent
  def handle_event("pick", %{"url" => url, "source" => source}, socket) do
    send(self(), {:image_picked, url, source})
    {:noreply, socket}
  end

  # top search hit only: providers already order by relevance/similarity,
  # and the operator judges the photo (name captioned) — a wrong match is
  # one glance, not a wrong import
  defp find_candidate(provider, query) do
    with {:ok, [top | _rest]} <- Providers.search_authors(provider.id, query, []),
         true <- name_plausible?(query, top.name),
         {:ok, image_url} <- candidate_image(provider, top) do
      %{name: top.name, image_url: image_url}
    else
      _no_candidate -> nil
    end
  end

  # Guards against confidently-wrong candidates: rreading-glasses author
  # search is book-relevance driven, so searching a narrator can surface
  # the book's *author* instead (Jefferson Mays → James S.A. Corey). Jaro
  # distance can't separate that case from legitimate name variants
  # ("Ty Franck" vs "Tyler Corey Franck" scores lower than the Corey
  # mismatch) — but sharing a name token does.
  defp name_plausible?(query, name) do
    not MapSet.disjoint?(name_tokens(query), name_tokens(name))
  end

  defp name_tokens(nil), do: MapSet.new()

  defp name_tokens(string) do
    string
    |> String.downcase()
    |> String.split(~r/[^\p{L}\p{N}]+/u, trim: true)
    |> Enum.filter(&(String.length(&1) >= 2))
    |> MapSet.new()
  end

  defp candidate_image(_provider, %{image_url: url}) when is_binary(url) and url != "",
    do: {:ok, url}

  defp candidate_image(provider, top) do
    case Providers.author_details(provider.id, top.id, []) do
      {:ok, %{image_url: url}} when is_binary(url) and url != "" -> {:ok, url}
      _no_image -> :no_image
    end
  end
end
