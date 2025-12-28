defmodule AmbryWeb.AudiobookLive do
  @moduledoc """
  LiveView for showing audiobook details.
  """

  use AmbryWeb, :live_view

  import Absinthe.Relay.Node, only: [to_global_id: 3]
  import AmbryWeb.Helpers.IdHelpers
  import AmbryWeb.TimeUtils, only: [duration_display: 1]

  alias Ambry.Books
  alias Ambry.Hashids
  alias Ambry.Media
  alias AmbryWeb.Player
  alias AmbryWeb.Player.PubSub.PlayerUpdated

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-md p-4 sm:max-w-none md:max-w-screen-2xl md:p-6 lg:p-8">
      <div class="justify-center sm:flex sm:flex-row">
        <section id="cover" class="mb-4 flex-none sm:mb-0 sm:w-80">
          <div class="mb-6 sm:hidden">
            <.book_header book={@media.book} />
            <p class="mt-4">
              Narrated by <.all_people_links people={@media.narrators} full_cast={@media.full_cast} />
              <%= if @media.abridged do %>
                <span>(Abridged)</span>
              <% end %>
            </p>
          </div>

          <div class={["aspect-1", if(!@media.thumbnails, do: "bg-zinc-200 dark:bg-zinc-800")]}>
            <img
              :if={@media.thumbnails}
              src={@media.thumbnails.extra_large}
              class="h-full w-full rounded-sm border border-zinc-200 object-cover object-center shadow-md dark:border-zinc-900 sm:w-80"
            />
          </div>

          <p class="mt-1 text-sm text-zinc-500">
            First published {format_published(@media.book)}
          </p>

          <div class="mt-6 divide-y divide-zinc-300 rounded-sm border border-zinc-200 bg-zinc-50 px-3 text-zinc-800 shadow-md dark:divide-zinc-800 dark:border-zinc-800 dark:bg-zinc-900 dark:text-zinc-200">
            <div class="flex items-center gap-4 py-3">
              <div class="grow">
                <p>{@media.book.title}</p>
                <p class="text-zinc-600 dark:text-zinc-400">
                  {duration_display(@media.duration)}
                </p>
              </div>
              <div class="cursor-pointer fill-current" phx-click={media_click_action(@player, @media)}>
                <%= if playing?(@player, @media) do %>
                  <FA.icon name="pause" class="h-12 w-12" />
                <% else %>
                  <FA.icon name="play" class="h-12 w-12 pl-1" />
                <% end %>
              </div>
            </div>
            <div :if={@media.publisher || @media.notes || @media.supplemental_files != []} class="space-y-2 py-3">
              <div>
                <p :if={@media.published} class="text-sm text-zinc-500">
                  Published {format_published(@media)}
                </p>
                <p :if={@media.publisher} class="text-sm text-zinc-500">by {@media.publisher}</p>
              </div>

              <p :if={@media.notes} class="text-sm text-zinc-500">
                {@media.notes}
              </p>

              <div :if={@media.supplemental_files != []} class="flex flex-col">
                <.brand_link :for={file <- @media.supplemental_files} href={file_href(file, @media)} target="_blank">
                  {format_file_name(file)}
                </.brand_link>
              </div>
            </div>
          </div>

          <section class="max-w-md sm:hidden">
            <.markdown :if={@media.description} content={@media.description} class="mt-4" />
          </section>

          <%= if @media.book.media != [] do %>
            <h2 class="mt-6 mb-2 text-2xl font-bold text-zinc-900 dark:text-zinc-100">
              Other Editions
            </h2>
            <div class="grid grid-cols-2 gap-4 sm:gap-6 md:gap-8">
              <.media_tile
                :for={media <- @media.book.media}
                media={media}
                show_title={false}
                show_authors={false}
                show_series={false}
                show_narrators={true}
                show_published={true}
              />
            </div>
          <% end %>
        </section>

        <section id="description" class="hidden max-w-md sm:ml-10 sm:block">
          <.book_header book={@media.book} />
          <p class="mt-4">
            Narrated by <.all_people_links people={@media.narrators} full_cast={@media.full_cast} />
            <%= if @media.abridged do %>
              <span>(Abridged)</span>
            <% end %>
          </p>
          <.markdown
            :if={@media.description}
            content={@media.description}
            class="mt-4 border-t border-zinc-200 pt-4 dark:border-zinc-900"
          />
        </section>
      </div>
    </div>
    """
  end

  @impl Phoenix.LiveView
  def mount(%{"id" => id_param}, _session, socket) do
    with {:ok, media_id} <- parse_id(id_param, :media),
         {:ok, media} <- Media.fetch_media_with_book_details(media_id) do
      if connected?(socket) do
        Player.subscribe!(socket.assigns.player)
      end

      global_id = to_global_id("Media", media.id, AmbrySchema)

      {:ok,
       assign(socket,
         page_title: Books.get_book_description(media.book),
         media: media,
         global_id: global_id
       )}
    else
      _ -> {:ok, redirect(socket, to: ~p"/")}
    end
  end

  @impl Phoenix.LiveView
  def handle_info(%PlayerUpdated{}, socket) do
    {:noreply, assign(socket, player: Player.reload!(socket.assigns.player))}
  end

  defp media_click_action(player, media) do
    if loaded?(player, media) do
      JS.dispatch("ambry:toggle-playback", to: "#media-player")
    else
      "ambry:load-and-play-media"
      |> JS.dispatch(to: "#media-player", detail: %{id: media.id})
      |> JS.navigate(~p"/")
    end
  end

  defp loaded?(%Player{player_state: %{media_id: media_id}}, %Media.Media{id: media_id}), do: true
  defp loaded?(_player, _media), do: false

  defp playing?(
         %Player{player_state: %{media_id: media_id}, playback_state: :playing},
         %Media.Media{id: media_id}
       ), do: true

  defp playing?(_player, _media), do: false

  defp format_file_name(file), do: file.label || file.filename

  defp file_href(file, media),
    do: ~p"/download/media/#{Hashids.encode(media.id)}/#{file.id}/#{file.filename}"
end
