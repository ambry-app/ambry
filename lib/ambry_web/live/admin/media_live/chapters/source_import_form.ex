defmodule AmbryWeb.Admin.MediaLive.Chapters.SourceImportForm do
  @moduledoc false
  use AmbryWeb, :live_component

  import AmbryWeb.Admin.Components

  alias Ambry.Media.Chapters
  alias Phoenix.LiveView.AsyncResult

  @impl Phoenix.LiveComponent
  def mount(socket) do
    {:ok, socket}
  end

  @impl Phoenix.LiveComponent
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign(
       strategies: Chapters.available_strategies(assigns.media),
       chapters: nil,
       select_strategy_form: to_form(%{}, as: :select_strategy),
       form: to_form(init_import_form_params(assigns.media), as: :import)
     )}
  end

  @impl Phoenix.LiveComponent
  def handle_async(:run_strategy, {:ok, chapters}, socket) do
    {:noreply, assign(socket, chapters: AsyncResult.ok(socket.assigns.chapters, chapters))}
  end

  def handle_async(:run_strategy, {:exit, {:shutdown, :cancel}}, socket) do
    {:noreply, assign(socket, chapters: AsyncResult.loading())}
  end

  def handle_async(:run_strategy, {:exit, {exception, _stacktrace}}, socket) do
    {:noreply,
     assign(socket,
       chapters: AsyncResult.failed(socket.assigns.chapters, exception.message)
     )}
  end

  @impl Phoenix.LiveComponent
  def handle_event("run-strategy", %{"select_strategy" => %{"strategy" => index_string}}, socket) do
    strategy = Enum.at(socket.assigns.strategies, String.to_integer(index_string))
    media = socket.assigns.media

    {:noreply,
     socket
     |> assign(
       chapters: AsyncResult.loading(),
       select_strategy_form: to_form(%{"strategy" => index_string}, as: :select_strategy)
     )
     |> cancel_async(:run_strategy)
     |> start_async(:run_strategy, fn -> run_strategy(strategy, media) end)}
  end

  def handle_event("import", %{"import" => import_params}, socket) do
    chapters = socket.assigns.chapters.result

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

  defp run_strategy(strategy, media) do
    case strategy.get_chapters(media) do
      {:ok, chapters} -> chapters
      {:error, reason} -> raise "Unhandled error: #{inspect(reason)}"
    end
  end

  defp init_import_form_params(media) do
    Map.new([:chapters], fn
      :chapters -> {"use_chapters", media.chapters == []}
    end)
  end
end
