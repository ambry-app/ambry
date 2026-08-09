defmodule AmbryWeb.Admin.MetadataLive.Providers do
  @moduledoc """
  Admin settings for the metadata provider registry: enable/disable
  providers, reorder priority, and edit provider settings (base URLs, API
  tokens) at runtime.
  """

  use AmbryWeb, :admin_live_view

  alias Ambry.Metadata.Providers
  alias Ambry.Metadata.Registry

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Metadata Providers")
     |> load_providers()}
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <.layout title={@page_title} user={@current_user}>
      <div class="mx-auto max-w-3xl space-y-8">
        <p class="text-zinc-500 dark:text-zinc-400">
          Providers fill in facts during import; you curate the structure. Priority controls the
          order providers are offered in import forms. Settings apply immediately; cached responses
          can be cleared per provider.
        </p>

        <section :for={{level, title, blurb} <- levels()}>
          <h2 class="mb-1 text-lg font-bold">{title}</h2>
          <p class="mb-4 text-sm text-zinc-500 dark:text-zinc-400">{blurb}</p>

          <div class="space-y-4">
            <div
              :for={entry <- providers_for_level(@providers, level)}
              class="rounded-sm border border-zinc-200 bg-zinc-50 p-4 dark:border-zinc-800 dark:bg-zinc-900"
            >
              <div class="flex items-center gap-3">
                <span class={[
                  "inline-block h-2.5 w-2.5 rounded-full",
                  (entry.enabled && "bg-lime-500") || "bg-zinc-400 dark:bg-zinc-600"
                ]} />
                <h3 class="grow font-semibold">{entry.display_name}</h3>

                <.button
                  :if={length(providers_for_level(@providers, level)) > 1}
                  color={:zinc}
                  phx-click="move"
                  phx-value-id={entry.id}
                  phx-value-direction="up"
                  class="!px-2 !py-1"
                  title="Higher priority"
                >
                  <.icon name="fa-chevron-up" class="h-3 w-3" />
                </.button>
                <.button
                  :if={length(providers_for_level(@providers, level)) > 1}
                  color={:zinc}
                  phx-click="move"
                  phx-value-id={entry.id}
                  phx-value-direction="down"
                  class="!px-2 !py-1"
                  title="Lower priority"
                >
                  <.icon name="fa-chevron-down" class="h-3 w-3" />
                </.button>

                <.button
                  color={(entry.enabled && :zinc) || :brand}
                  phx-click="toggle"
                  phx-value-id={entry.id}
                  class="!px-2 !py-1"
                >
                  {(entry.enabled && "Disable") || "Enable"}
                </.button>
              </div>

              <div class="mt-2 flex flex-wrap gap-2">
                <span
                  :for={capability <- entry.capabilities}
                  class="rounded-sm bg-zinc-200 px-2 py-0.5 text-xs text-zinc-600 dark:bg-zinc-800 dark:text-zinc-400"
                >
                  {capability_label(capability, entry.level)}
                </span>
              </div>

              <div :for={{level, message} <- notices(entry)} class="mt-2">
                <p class={["flex items-center gap-2 text-sm", notice_class(level)]}>
                  <.icon name={notice_icon(level)} class="h-4 w-4 flex-none" />
                  {message}
                </p>
              </div>

              <form
                :if={entry.module.config_fields() != []}
                id={"provider-config-#{entry.id}"}
                phx-submit="save-config"
                class="mt-4 space-y-4"
              >
                <input type="hidden" name="provider_id" value={entry.id} />
                <div :for={field <- entry.module.config_fields()}>
                  <.input
                    type={(field.type == :secret && "password") || "text"}
                    label={field.label}
                    name={"config[#{field.key}]"}
                    value={display_value(entry.config[field.key], field)}
                    placeholder={field.default}
                  />
                  <p :if={field.help} class="mt-1 text-xs text-zinc-500 dark:text-zinc-400">
                    {field.help}
                  </p>
                </div>
                <div class="flex gap-2">
                  <.button type="submit">Save</.button>
                  <.button
                    type="button"
                    color={:zinc}
                    phx-click="clear-cache"
                    phx-value-id={entry.id}
                    data-confirm={"Clear all cached #{entry.display_name} responses?"}
                  >
                    Clear cache
                  </.button>
                </div>
              </form>

              <div :if={entry.module.config_fields() == []} class="mt-4">
                <.button
                  type="button"
                  color={:zinc}
                  phx-click="clear-cache"
                  phx-value-id={entry.id}
                  data-confirm={"Clear all cached #{entry.display_name} responses?"}
                >
                  Clear cache
                </.button>
              </div>
            </div>
          </div>
        </section>
      </div>
    </.layout>
    """
  end

  @impl Phoenix.LiveView
  def handle_event("toggle", %{"id" => provider_id}, socket) do
    {:ok, entry} = Registry.fetch(provider_id)
    {:ok, _row} = Registry.update(provider_id, %{enabled: !entry.enabled})

    {:noreply, load_providers(socket)}
  end

  def handle_event("move", %{"id" => provider_id, "direction" => direction}, socket) do
    entries = socket.assigns.providers
    ids = Enum.map(entries, & &1.id)
    index = Enum.find_index(ids, &(&1 == provider_id))

    swap_with =
      case direction do
        "up" -> index - 1
        "down" -> index + 1
      end

    if swap_with in 0..(length(ids) - 1)//1 do
      reordered =
        ids
        |> List.replace_at(index, Enum.at(ids, swap_with))
        |> List.replace_at(swap_with, provider_id)

      reordered
      |> Enum.with_index()
      |> Enum.each(fn {id, priority} ->
        {:ok, _row} = Registry.update(id, %{priority: priority})
      end)
    end

    {:noreply, load_providers(socket)}
  end

  def handle_event("save-config", %{"provider_id" => provider_id} = params, socket) do
    {:ok, _row} = Registry.update(provider_id, %{config: params["config"] || %{}})

    {:noreply,
     socket
     |> load_providers()
     |> put_flash(:info, "Provider settings saved.")}
  end

  def handle_event("clear-cache", %{"id" => provider_id}, socket) do
    Providers.clear_cache(provider_id)

    {:noreply, put_flash(socket, :info, "Cache cleared.")}
  end

  defp load_providers(socket) do
    assign(socket, :providers, Registry.all())
  end

  defp providers_for_level(providers, level) do
    Enum.filter(providers, &(&1.level == level))
  end

  defp levels do
    [
      {:work, "Work-level providers",
       "Books, authors, and series — the abstract side of the library."},
      {:recording, "Recording-level providers",
       "Audiobook releases — narrators, square covers, and chapters, keyed by ASIN."},
      {:person, "Person-level providers",
       "Bios and photos for the humans behind authors and narrators — keyed on real people, not published-as names."}
    ]
  end

  defp notices(entry), do: Ambry.Metadata.Provider.config_notices(entry.module, entry.config)

  defp notice_class(:info), do: "text-zinc-500 dark:text-zinc-400"
  defp notice_class(:warning), do: "text-amber-600 dark:text-amber-500"
  defp notice_class(:error), do: "text-red-600 dark:text-red-500"

  defp notice_icon(:info), do: "fa-circle-info"
  defp notice_icon(:warning), do: "fa-triangle-exclamation"
  defp notice_icon(:error), do: "fa-circle-exclamation"

  # A capability means something different at each level, and the level is
  # what says which — a recording-level `:book_search` searches *audiobooks*,
  # a work-level one searches works. Labelling both "book search" threw that
  # away and made the provider list look like it couldn't tell them apart.
  #
  # Kept as display rather than split into `:work_search`/`:recording_search`
  # atoms deliberately: the level already carries it, and separate atoms would
  # let a provider claim recording-search at the work level — an illegal state
  # the current pairing simply can't represent.
  defp capability_label(:book_search, :recording), do: "audiobook search"
  defp capability_label(:book_details, :recording), do: "audiobook details"
  defp capability_label(:book_search, _level), do: "work search"
  defp capability_label(:book_details, _level), do: "work details"
  defp capability_label(:author_search, :person), do: "person search"
  defp capability_label(:author_details, :person), do: "person details"
  defp capability_label(:author_search, _level), do: "author search"
  defp capability_label(:author_details, _level), do: "author details"
  defp capability_label(:chapters, _level), do: "chapters"
  defp capability_label(:editions, _level), do: "editions"

  # A capability with no label must not take the settings page down with it —
  # adding one to the behaviour shouldn't be able to break an unrelated screen.
  defp capability_label(other, _level), do: other |> to_string() |> String.replace("_", " ")

  defp display_value(value, %{default: default}) when value == default, do: nil
  defp display_value(value, _field), do: value
end
