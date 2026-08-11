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
  alias Ambry.Media.Editions

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-md p-4 sm:max-w-none md:max-w-screen-2xl md:p-6 lg:p-8">
      <div class="justify-center sm:flex sm:flex-row">
        <section id="cover" class="mb-4 flex-none sm:mb-0 sm:w-80">
          <div class="mb-6 sm:hidden">
            <.book_header book={@media.book} title_override={media_display_title(@media)} />
            <p class="mt-4">
              Narrated by <.all_people_links people={@media.narrators} full_cast={@media.full_cast} />
              <%= if @media.abridged do %>
                <span>(Abridged)</span>
              <% end %>
            </p>
          </div>

          <div class={["aspect-1", if(!@media.thumbnails, do: "bg-zinc-800")]}>
            <img
              :if={@media.thumbnails}
              src={@media.thumbnails.extra_large}
              class="h-full w-full rounded-sm border border-zinc-900 object-cover object-center shadow-md sm:w-80"
            />
          </div>

          <p class="mt-1 text-sm text-zinc-500">
            First published {format_published(@media.book)}
          </p>

          <div class="mt-6 divide-y divide-zinc-800 rounded-lg bg-zinc-900 px-3 text-zinc-200 shadow-md">
            <div class="flex items-center gap-4 py-3">
              <div class="grow">
                <p>{media_display_title(@media)}</p>
                <p :if={part_set_line(@media)} class="text-zinc-400">
                  {part_set_line(@media)}
                </p>
                <p class="text-zinc-400">
                  {duration_display(@media.duration)}
                </p>
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

          <%= if @part_set do %>
            <%= if @part_set.show_label && @part_set.name do %>
              <h2 class="mt-6 text-2xl font-bold text-zinc-100">
                {@part_set.name}
              </h2>
              <p class="mb-2 text-sm text-zinc-400">
                {part_set_label(@part_set)}
              </p>
            <% else %>
              <h2 class="mt-6 mb-2 text-2xl font-bold text-zinc-100">
                {part_set_label(@part_set)}
              </h2>
            <% end %>
            <div class="grid grid-cols-3 gap-4 sm:gap-6">
              <div :for={part <- @part_set.media} class="text-center">
                <%= if part.id == @media.id do %>
                  <div class="ring-brand-dark rounded-sm ring-2">
                    <.book_multi_image thumbnails={if part.thumbnails, do: [part.thumbnails], else: []} />
                  </div>
                  <p class="mt-1 text-sm font-bold text-zinc-100">
                    {part_chip_label(part, @part_set)}
                  </p>
                <% else %>
                  <.link navigate={~p"/audiobooks/#{part}"} class="group">
                    <.book_multi_image thumbnails={if part.thumbnails, do: [part.thumbnails], else: []} />
                    <p class="mt-1 text-sm text-zinc-200 group-hover:underline">
                      {part_chip_label(part, @part_set)}
                    </p>
                  </.link>
                <% end %>
              </div>
            </div>
          <% end %>

          <%= if @other_editions != [] do %>
            <h2 class="mt-6 mb-2 text-2xl font-bold text-zinc-100">
              Other Editions
            </h2>
            <div class="grid grid-cols-2 gap-4 sm:gap-6 md:gap-8">
              <.edition_tile
                :for={edition <- @other_editions}
                edition={edition}
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
          <.book_header book={@media.book} title_override={media_display_title(@media)} />
          <p class="mt-4">
            Narrated by <.all_people_links people={@media.narrators} full_cast={@media.full_cast} />
            <%= if @media.abridged do %>
              <span>(Abridged)</span>
            <% end %>
          </p>
          <.markdown
            :if={@media.description}
            content={@media.description}
            class="mt-4 border-t border-zinc-900 pt-4"
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
      global_id = to_global_id("Media", media.id, AmbrySchema)

      part_set =
        case media.recording_group do
          %{media: [_, _ | _]} = group -> group
          _no_set -> nil
        end

      # true alternates only: every other edition of the book, minus this
      # media's own part set (its parts live in the rail above). Siblings are
      # dropped before grouping — book.media already excludes the current
      # media, and a lone leftover part would otherwise present as a single
      # edition (one-part groups collapse) and sneak past a post-hoc reject.
      other_editions =
        media.book.media
        |> Enum.reject(
          &(media.recording_group_id && &1.recording_group_id == media.recording_group_id)
        )
        |> Editions.from_media()

      {:ok,
       assign(socket,
         page_title: Books.get_book_description(media.book),
         media: media,
         part_set: part_set,
         other_editions: other_editions,
         global_id: global_id
       )}
    else
      _ -> {:ok, redirect(socket, to: ~p"/")}
    end
  end

  # short label under each cover in the part rail
  defp part_chip_label(part, group) do
    Ambry.Media.Media.part_label(part, group) || part.title || "Untitled"
  end

  # "Part 2 of 3" / "Episode 4 of 6" / nil — the group name renders in the
  # parts-rail heading (when the group opts in via show_label), not here
  defp part_set_line(media) do
    Ambry.Media.Media.part_label(media)
  end

  defp format_file_name(file), do: file.label || file.filename

  defp file_href(file, media),
    do: ~p"/download/media/#{Hashids.encode(media.id)}/#{file.id}/#{file.filename}"
end
