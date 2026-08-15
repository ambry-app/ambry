defmodule AmbryWeb.Admin.SettingsLive.Index do
  @moduledoc """
  Server settings that aren't about any one record.
  """

  use AmbryWeb, :admin_live_view

  alias Ambry.Library.NamingTemplate
  alias Ambry.Media
  alias Ambry.Settings

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Settings")
     |> assign_settings()}
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <.layout title={@page_title} user={@current_user} jobs={@admin_jobs}>
      <div class="max-w-4xl space-y-8">
        <section>
          <h2 class="mb-1 text-lg font-bold">Direct play</h2>
          <p class="mb-4 text-sm text-zinc-400">
            Direct-play audiobooks are served as their original files, with no transcoding or
            packaging. Leave this off until every client app understands tracks; older builds
            can't play them.
          </p>

          <div class="rounded-lg bg-zinc-900 p-4">
            <div class="flex items-center gap-3">
              <span class={[
                "inline-block h-2.5 w-2.5 rounded-full",
                (@direct_play_publishing && "bg-lime-500") || "bg-zinc-600"
              ]} />
              <div class="grow">
                <h3 class="font-semibold">Publish direct-play audiobooks</h3>
                <p class="text-sm text-zinc-400">
                  {publishing_blurb(@direct_play_publishing)}
                </p>
              </div>

              <.button phx-click="toggle-direct-play-publishing">
                {(@direct_play_publishing && "Turn off") || "Turn on"}
              </.button>
            </div>
          </div>
        </section>

        <section>
          <h2 class="mb-1 text-lg font-bold">Library naming</h2>
          <p class="mb-4 text-sm text-zinc-400">
            How managed audiobooks are organized inside a library root. Files imported from a
            downloads folder are placed here; external collections are never reorganized.
          </p>

          <.simple_form
            id="naming-template-form"
            for={@template_form}
            phx-change="validate-template"
            phx-submit="save-template"
            autocomplete="off"
          >
            <.input field={@template_form[:template]} label="Folder template" />

            <p class="text-sm text-zinc-400">
              Available: {Enum.map_join(NamingTemplate.tokens(), ", ", &"{#{&1}}")}. A book with
              several authors or series uses the first one. Empty parts collapse.
            </p>

            <div class="rounded-lg bg-zinc-900 p-4">
              <p class="mb-1 text-xs font-semibold text-zinc-400">Preview</p>
              <p class="font-mono break-all text-sm" data-role="template-preview">{@preview}</p>
            </div>

            <:actions>
              <.button disabled={@template_error != nil}>Save</.button>
            </:actions>
          </.simple_form>
        </section>
      </div>
    </.layout>
    """
  end

  @impl Phoenix.LiveView
  def handle_event("toggle-direct-play-publishing", _params, socket) do
    enabled? = !socket.assigns.direct_play_publishing
    {:ok, _setting} = Settings.set_direct_play_publishing(enabled?)

    # Turning it on releases everything that piled up behind it. Turning it
    # off deliberately does nothing to what's already published — the switch
    # governs the act of publishing, not the recordings that got through.
    if enabled?, do: {:ok, _job} = Media.publish_pending_direct_play_async()

    {:noreply, assign_settings(socket)}
  end

  def handle_event("validate-template", %{"settings" => %{"template" => template}}, socket) do
    {:noreply, assign_template(socket, template)}
  end

  def handle_event("save-template", %{"settings" => %{"template" => template}}, socket) do
    case Settings.set_library_naming_template(template) do
      {:ok, _setting} ->
        {:noreply,
         socket |> put_flash(:info, "Saved the naming template.") |> assign_template(template)}

      {:error, reason} ->
        {:noreply,
         socket
         |> put_flash(:error, "Can't use that template: #{template_error(reason)}")
         |> assign_template(template)}
    end
  end

  defp assign_settings(socket) do
    socket
    |> assign(:direct_play_publishing, Settings.direct_play_publishing?())
    |> assign_template(Settings.library_naming_template())
  end

  # A live preview against a worked example, because a template's failure mode
  # is a folder tree you don't notice is wrong until it's full of files.
  @example %{
    author: "Brandon Sanderson",
    series: "The Stormlight Archive",
    series_book_number: "1",
    narrator: "Michael Kramer",
    title: "The Way of Kings",
    year: 2010
  }

  defp assign_template(socket, template) do
    error = with :ok <- NamingTemplate.validate(template), do: nil

    preview =
      case error do
        nil ->
          {:ok, folder} = NamingTemplate.render(template, @example)
          # With the token, because the preview's whole job is showing what
          # the tree actually looks like — and every file in it carries one.
          {:ok, filename} = NamingTemplate.filename(@example, "book.m4b", %{token: "7bKq"})
          Path.join([folder, filename])

        {:error, reason} ->
          template_error(reason)
      end

    assign(socket,
      template_form: to_form(%{"template" => template}, as: :settings),
      template_error: error,
      preview: preview
    )
  end

  defp template_error(:blank), do: "it can't be empty"

  defp template_error(:absolute),
    do: "it can't start with /; paths are relative to a library root"

  defp template_error(:traversal), do: "it can't contain .."
  defp template_error(:no_title_token), do: "it needs {title}, or every book shares one folder"
  defp template_error({:unknown_token, token}), do: "there's no {#{token}} token"

  defp publishing_blurb(true), do: "Scanned audiobooks can be made visible to clients."

  defp publishing_blurb(false),
    do:
      "Audiobooks can be scanned, but one with only direct-play files can't be marked ready. " <>
        "The old transcoding pipeline is unaffected."
end
