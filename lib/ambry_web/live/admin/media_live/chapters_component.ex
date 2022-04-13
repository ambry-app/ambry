defmodule AmbryWeb.Admin.MediaLive.ChaptersComponent do
  @moduledoc false

  use AmbryWeb, :p_live_component

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
     |> assign(changeset: changeset)}
  end

  def update(%{chapters: chapters_response}, socket) do
    # the parent live view has run the chapter strategy and has sent us a result
    %{media: media} = socket.assigns

    socket =
      case chapters_response do
        {:ok, chapters} ->
          changeset = Media.change_media(media, %{chapters: chapters}, for: :update)

          assign(socket,
            show_strategies: false,
            strategy_error: nil,
            strategies: [],
            running_strategy: false,
            changeset: changeset
          )

        {:error, error} ->
          assign(socket, running_strategy: false, strategy_error: error)
      end

    {:ok, socket}
  end

  @impl Phoenix.LiveComponent
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

  defp save_media(socket, media_params) do
    case Media.update_media(socket.assigns.media, media_params, for: :update) do
      {:ok, _media} ->
        {:noreply,
         socket
         |> put_flash(:info, "Media updated successfully")
         |> push_redirect(to: socket.assigns.return_to)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, changeset: changeset)}
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
end
