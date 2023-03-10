defmodule AmbryWeb.Admin.MediaLive.ChaptersComponent do
  @moduledoc false

  use AmbryWeb, :live_component

  alias Ambry.Media
  alias Ambry.Media.Chapters

  @impl Phoenix.LiveComponent
  def mount(socket) do
    {:ok, socket}
  end

  @impl Phoenix.LiveComponent
  def update(%{media: media} = assigns, socket) do
    changeset = Media.change_media(media, %{}, for: :update)

    {:ok,
     socket
     |> assign(assigns)
     |> default_assigns()
     |> assign_form(changeset)}
  end

  def update(%{chapters: chapters_response}, socket) do
    # the parent live view has run the chapter strategy and has sent us a result
    %{media: media} = socket.assigns

    socket =
      case chapters_response do
        {:ok, chapters} ->
          changeset = Media.change_media(media, %{chapters: chapters}, for: :update)

          socket
          |> assign(
            show_strategies: false,
            strategy_error: nil,
            strategies: [],
            running_strategy: false
          )
          |> assign_form(changeset)

        {:error, error} ->
          assign(socket, running_strategy: false, strategy_error: error)
      end

    {:ok, socket}
  end

  @impl Phoenix.LiveComponent
  def handle_event("validate", %{"media" => media_params}, socket) do
    changeset =
      socket.assigns.media
      |> Media.change_media(media_params, for: :update)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"media" => media_params}, socket) do
    save_media(socket, media_params)
  end

  def handle_event("show-strategies", _params, socket) do
    strategies = Chapters.available_strategies(socket.assigns.media)

    {:noreply,
     assign(socket,
       show_strategies: true,
       strategies: strategies
     )}
  end

  def handle_event("hide-strategies", _params, socket) do
    {:noreply,
     assign(socket,
       show_strategies: false,
       strategy_error: nil,
       strategies: []
     )}
  end

  def handle_event("run-strategy", %{"strategy" => num}, socket) do
    %{strategies: strategies} = socket.assigns

    strategy = Enum.at(strategies, String.to_integer(num))

    # run strategy async (handled in parent live view)
    send(self(), {:run_strategy, strategy})

    {:noreply,
     assign(socket,
       running_strategy: true
     )}
  end

  def handle_event("delete-chapter", %{"idx" => idx}, socket) do
    index = String.to_integer(idx)
    chapters = Ecto.Changeset.fetch_field!(socket.assigns.form.source, :chapters)

    chapters =
      chapters
      |> List.delete_at(index)
      |> Enum.map(fn chapter -> %{"time" => to_string(chapter.time), "title" => chapter.title} end)

    changeset = Media.change_media(socket.assigns.media, %{chapters: chapters}, for: :update)

    {:noreply, assign_form(socket, changeset)}
  end

  defp save_media(socket, media_params) do
    case Media.update_media(socket.assigns.media, media_params, for: :update) do
      {:ok, _media} ->
        {:noreply,
         socket
         |> put_flash(:info, "Media updated successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp default_assigns(socket) do
    assign(socket,
      show_strategies: false,
      strategy_error: nil,
      strategies: [],
      running_strategy: false
    )
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset))
  end
end
