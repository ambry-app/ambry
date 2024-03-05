defmodule AmbryWeb.Admin.MediaLive.Chapters.SourceImportForm do
  @moduledoc false
  use AmbryWeb, :live_component

  import AmbryWeb.Admin.Components

  alias Ambry.Media.Chapters

  @impl Phoenix.LiveComponent
  def mount(socket) do
    {:ok, socket}
  end

  @impl Phoenix.LiveComponent
  def update(assigns, socket) do
    socket =
      case Map.pop(assigns, :info) do
        {nil, assigns} ->
          socket
          |> assign(assigns)
          |> assign(
            strategies: Chapters.available_strategies(assigns.media),
            strategy_form: to_form(%{}, as: :strategy),
            chapters_loading: false,
            chapters: nil
          )

        {forwarded_info_payload, assigns} ->
          socket
          |> assign(assigns)
          |> then(fn socket ->
            handle_forwarded_info(forwarded_info_payload, socket)
          end)
      end

    {:ok, socket}
  end

  @impl Phoenix.LiveComponent
  def handle_event("run-strategy", %{"strategy" => %{"strategy" => index_string}}, socket) do
    strategy = Enum.at(socket.assigns.strategies, String.to_integer(index_string))
    {:noreply, async_run_strategy(socket, strategy)}
  end

  def handle_event("import", %{"import" => import_params}, socket) do
    chapters = socket.assigns.chapters

    import_type =
      cond do
        Map.has_key?(import_params, "titles_only") -> :titles_only
        Map.has_key?(import_params, "times_only") -> :times_only
        true -> :all
      end

    params =
      if import_params["use_chapters"] == "true" do
        %{"chapters" => build_chapters_params(chapters, import_type)}
      else
        %{}
      end

    send(self(), {:import, %{"media" => params}})

    {:noreply, socket}
  end

  defp build_chapters_params(chapters, import_type) do
    Enum.map(chapters, &build_chapter_params(&1, import_type))
  end

  defp build_chapter_params(chapter, :titles_only), do: %{"title" => chapter.title}
  defp build_chapter_params(chapter, :times_only), do: %{"time" => chapter.time}

  defp build_chapter_params(chapter, :all),
    do: %{"title" => chapter.title, "time" => chapter.time}

  defp handle_forwarded_info({:chapters, {:ok, chapters}}, socket) do
    assign(socket, chapters_loading: false, chapters: chapters)
  end

  defp handle_forwarded_info({:chapters, {:error, _reason}}, socket) do
    socket
    |> put_flash(:error, "extracting chapters failed")
    |> assign(chapters_loading: false)
  end

  defp async_run_strategy(socket, strategy) do
    Task.async(fn ->
      response = strategy.get_chapters(socket.assigns.media)
      {{:for, __MODULE__, socket.assigns.id}, {:chapters, response}}
    end)

    assign(socket,
      chapters_loading: true,
      chapters: nil,
      form: to_form(init_import_form_params(socket.assigns.media), as: :import)
    )
  end

  defp init_import_form_params(media) do
    Map.new([:chapters], fn
      :chapters -> {"use_chapters", media.chapters == []}
    end)
  end
end
