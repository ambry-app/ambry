defmodule AmbryWeb.Admin.SettingsLive.Index do
  @moduledoc """
  Server settings that aren't about any one record.
  """

  use AmbryWeb, :admin_live_view

  alias Ambry.Library.NamingTemplate
  alias Ambry.Media
  alias Ambry.Search
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
    <.layout title={@page_title} user={@current_user} socket={@socket}>
      <div class="-mb-4 max-w-4xl space-y-14">
        <.form_section title="Direct play">
          <:blurb>
            Audiobooks served as the files they already are. Older client builds can't play
            them.
          </:blurb>

          <.field_group>
            <div class="flex items-center gap-3 pl-3">
              <.status_dot on={@direct_play_publishing} />

              <div class="grow">
                <p class="text-sm font-semibold text-zinc-200">Publish direct-play audiobooks</p>
                <p class="text-sm text-zinc-400">{publishing_blurb(@direct_play_publishing)}</p>
              </div>

              <.button color={:zinc} size={:sm} phx-click="toggle-direct-play-publishing">
                {(@direct_play_publishing && "Turn off") || "Turn on"}
              </.button>
            </div>
          </.field_group>
        </.form_section>

        <.form_section title="Search index">
          <:blurb>
            The index keeps itself current. Rebuild after an upgrade that changes what a
            record holds.
          </:blurb>

          <.field_group>
            <div class="flex items-center gap-3 pl-3">
              <.status_dot on={@index.pending == 0} attention={true} />

              <div class="grow">
                <p class="text-sm font-semibold text-zinc-200" data-role="index-records">
                  {@index.records} {ngettext("record", "records", @index.records)}
                </p>
                <p class="text-sm text-zinc-400" data-role="index-state">{index_blurb(@index)}</p>
              </div>

              <.button color={:zinc} size={:sm} phx-click="reindex">Rebuild</.button>
            </div>
          </.field_group>
        </.form_section>

        <.simple_form
          id="naming-template-form"
          for={@template_form}
          phx-change="validate-template"
          phx-submit="save-template"
          autocomplete="off"
        >
          <.form_section title="Library naming">
            <:blurb>How imported audiobooks are organized inside a library root.</:blurb>

            <.field_group
              label="Folder template"
              hint={Enum.map_join(NamingTemplate.tokens(), " ", &"{#{&1}}")}
            >
              <.input field={@template_form[:template]} />

              <div>
                <.label class="pl-3">Preview</.label>
                <p class="font-mono break-all pt-1 pl-3 text-sm" data-role="template-preview">
                  {@preview}
                </p>
              </div>
            </.field_group>
          </.form_section>

          <.form_footer>
            <.button disabled={@template_error != nil}>Save</.button>
          </.form_footer>
        </.simple_form>
      </div>
    </.layout>
    """
  end

  @impl Phoenix.LiveView
  def handle_event("toggle-direct-play-publishing", _params, socket) do
    enabled? = !socket.assigns.direct_play_publishing
    {:ok, _setting} = Settings.set_direct_play_publishing(enabled?)

    # Turning it on releases what piled up behind it. Turning it off governs
    # the act of publishing, not the recordings that already got through.
    if enabled?, do: {:ok, _job} = Media.publish_pending_direct_play_async()

    {:noreply, assign_settings(socket)}
  end

  def handle_event("reindex", _params, socket) do
    :ok = Search.reindex_all!()

    {:noreply,
     socket
     |> put_flash(:info, "Rebuilding the search index in the background.")
     |> assign_settings()}
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
    |> assign(:index, Search.stats())
    |> assign_template(Settings.library_naming_template())
  end

  # A count that is up says "still going", never "broken": it is only worth
  # reading if it stays up.
  defp index_blurb(%{pending: 0}), do: "Up to date."

  defp index_blurb(%{pending: pending}),
    do: "Catching up on #{pending} #{ngettext("change", "changes", pending)}."

  # A template's failure mode is a folder tree nobody notices is wrong until
  # it is full of files, so it renders against an example as it is typed.
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
          # With the token: every file in a root carries one.
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
  defp template_error(:absolute), do: "it can't start with /"
  defp template_error(:traversal), do: "it can't contain .."
  defp template_error(:no_title_token), do: "it needs {title}, or every book shares one folder"
  defp template_error({:unknown_token, token}), do: "there's no {#{token}} token"

  defp publishing_blurb(true), do: "New audiobooks can be published."
  defp publishing_blurb(false), do: "Audiobooks with only direct-play files stay unpublished."
end
