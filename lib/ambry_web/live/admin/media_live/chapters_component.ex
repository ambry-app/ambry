defmodule AmbryWeb.Admin.MediaLive.ChaptersComponent do
  @moduledoc false

  use AmbryWeb, :live_component

  import AmbryWeb.Admin.ParamHelpers

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

  def update(%{chapters: chapters_response} = params, socket) do
    # the parent live view has run the chapter strategy and has sent us a result
    socket =
      case chapters_response do
        {:ok, chapters} ->
          handle_chapter_import(socket, chapters, params[:import_mode])

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

  def handle_event("submit", %{"media" => media_params}, socket) do
    case media_params do
      %{"apply_shift" => "true"} = params -> apply_shift(socket, params)
      params -> save_media(socket, params)
    end
  end

  def handle_event("show-strategies", _params, socket) do
    strategies = Chapters.available_strategies(socket.assigns.media)

    {:noreply,
     assign(socket,
       strategy_form: to_form(%{}, as: :strategy),
       strategies: strategies
     )}
  end

  def handle_event("hide-strategies", _params, socket) do
    {:noreply,
     assign(socket,
       strategy_form: nil,
       strategy_error: nil,
       strategies: [],
       selected_strategy: nil
     )}
  end

  def handle_event("strategy-validate", %{"strategy" => params}, socket) do
    selected_strategy = get_selected_strategy(params, socket.assigns.strategies)

    {:noreply,
     assign(
       socket,
       selected_strategy: selected_strategy,
       strategy_form: to_form(params, as: :strategy)
     )}
  end

  def handle_event("strategy-submit", %{"strategy" => params}, socket) do
    case get_selected_strategy(params, socket.assigns.strategies) do
      nil ->
        {:noreply, assign(socket, strategy_error: "Please select a strategy")}

      strategy ->
        strategy_params = Map.delete(params, "strategy")
        send(self(), {:run_strategy, strategy, strategy_params})

        {:noreply, assign(socket, running_strategy: true, strategy_form: nil, selected_strategy: nil)}
    end
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

  defp apply_shift(socket, media_params) do
    shift = Decimal.new(media_params["shift"])

    params =
      Map.update!(media_params, "chapters", fn chapters ->
        chapters
        |> map_to_list()
        |> Enum.map(&apply_shift_to_chapter(&1, shift))
      end)

    changeset =
      socket.assigns.media
      |> Media.change_media(params, for: :update)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  defp apply_shift_to_chapter(chapter, shift) do
    Map.update!(chapter, "time", fn time ->
      time = Decimal.new(time)

      case Decimal.compare(time, 0) do
        :lt -> "0.00"
        :eq -> "0.00"
        :gt -> time |> Decimal.add(shift) |> Decimal.to_string()
      end
    end)
  end

  defp get_selected_strategy(params, strategies) do
    case params do
      %{"strategy" => ""} -> nil
      %{"strategy" => index_str} -> Enum.at(strategies, String.to_integer(index_str))
      _params -> nil
    end
  end

  defp handle_chapter_import(socket, chapters, import_mode) when import_mode in ["full", "", nil] do
    finalize_chapter_import(socket, chapters)
  end

  defp handle_chapter_import(socket, new_chapters, import_mode) when import_mode in ["time_only", "title_only"] do
    media = socket.assigns.media
    existing_chapters = media.chapters

    if length(existing_chapters) == length(new_chapters) do
      chapters =
        existing_chapters
        |> Enum.zip(new_chapters)
        |> Enum.map(fn {existing_chapter, new_chapter} ->
          chapter_params_for_import_mode(existing_chapter, new_chapter, import_mode)
        end)

      finalize_chapter_import(socket, chapters)
    else
      assign(socket,
        strategy_error:
          "Count of imported chapters (#{length(new_chapters)}) does not match count of existing chapters (#{length(existing_chapters)})"
      )
    end
  end

  defp chapter_params_for_import_mode(existing_chapter, new_chapter, "title_only") do
    %{time: existing_chapter.time, title: new_chapter.title}
  end

  defp chapter_params_for_import_mode(existing_chapter, new_chapter, "time_only") do
    %{time: new_chapter.time, title: existing_chapter.title}
  end

  defp finalize_chapter_import(socket, chapters) do
    media = socket.assigns.media
    changeset = Media.change_media(media, %{chapters: chapters}, for: :update)

    socket
    |> assign(
      show_strategies: false,
      strategy_error: nil,
      strategies: [],
      running_strategy: false
    )
    |> assign_form(changeset)
  end

  defp default_assigns(socket) do
    assign(socket,
      strategy_form: nil,
      strategy_error: nil,
      strategies: [],
      running_strategy: false,
      selected_strategy: nil
    )
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset))
  end
end
