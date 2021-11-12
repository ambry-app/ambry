defmodule AmbryWeb.Admin.MediaLive.ChaptersComponent do
  @moduledoc false

  use AmbryWeb, :live_component

  alias Ambry.Media
  alias Ambry.Media.Chapters
  alias AmbryWeb.Admin.Components.{Button, SaveButton}

  alias Surface.Components.Form

  alias Surface.Components.Form.{
    Field,
    HiddenInput,
    Inputs,
    TextInput
  }

  prop title, :string, required: true
  prop media, :any, required: true
  prop return_to, :string, required: true

  data show_strategies, :boolean, default: false
  data strategies, :list, default: []
  data strategy_error, :atom, default: nil

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
     |> assign(changeset: changeset)}
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
    %{strategies: strategies, media: media} = socket.assigns

    strategy = Enum.at(strategies, String.to_integer(num))

    socket =
      case strategy.get_chapters(media) do
        {:ok, chapters} ->
          changeset = Media.change_media(media, %{chapters: chapters}, for: :update)

          assign(socket,
            show_strategies: false,
            strategy_error: nil,
            strategies: [],
            changeset: changeset
          )

        {:error, error} ->
          assign(socket, strategy_error: error)
      end

    {:noreply, socket}
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
end
