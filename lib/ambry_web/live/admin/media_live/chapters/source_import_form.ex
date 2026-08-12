defmodule AmbryWeb.Admin.MediaLive.Chapters.SourceImportForm do
  @moduledoc """
  Re-reading a recording's chapter markers off its own files.

  This used to offer a menu of three extraction strategies — "Each MP3 is a
  chapter", "MP4 chapters", and so on — which asked the operator to know
  something about containers in order to answer a question the files already
  answer themselves. It is one action now, and it is the same code the
  scanner runs (`Ambry.Media.Chapters.FromFiles`), so what an import produces
  here is exactly what an import would have produced.

  Two ways to take it, because markers and titles are separate facts:

    * **markers and titles** — the whole list as the files state it;
    * **markers only** — the new timeline, with the titles already on the
      record poured back onto it by the same duration alignment a provider
      merge uses. This is what to click after fixing a file: the curation
      survives, the timeline is corrected.
  """
  use AmbryWeb, :live_component

  import AmbryWeb.Admin.MediaLive.Chapters.Preview

  alias Ambry.Media.Chapters.Merge
  alias Ambry.Media.Scanner
  alias Phoenix.LiveView.AsyncResult

  @impl Phoenix.LiveComponent
  def update(assigns, socket) do
    media = assigns.media

    {:ok,
     socket
     |> assign(assigns)
     |> assign(read: AsyncResult.loading())
     |> start_async(:read, fn -> read(media) end)}
  end

  @impl Phoenix.LiveComponent
  def handle_async(:read, {:ok, result}, socket) do
    {:noreply, assign(socket, read: AsyncResult.ok(socket.assigns.read, result))}
  end

  def handle_async(:read, {:exit, {:shutdown, :cancel}}, socket) do
    {:noreply, assign(socket, read: AsyncResult.loading())}
  end

  def handle_async(:read, {:exit, {exception, _stacktrace}}, socket) do
    {:noreply, assign(socket, read: AsyncResult.failed(socket.assigns.read, message(exception)))}
  end

  @impl Phoenix.LiveComponent
  def handle_event("import-all", _params, socket) do
    %{chapters: chapters, marker_source: source} = socket.assigns.read.result
    send(self(), {:chapters, chapters, source})

    {:noreply, socket}
  end

  def handle_event("import-markers", _params, socket) do
    %{chapters: chapters, marker_source: source} = socket.assigns.read.result
    {merged, _alignment} = Merge.titles(chapters, socket.assigns.markers, :manual)
    send(self(), {:chapters, restore_sources(merged, socket.assigns.markers), source})

    {:noreply, socket}
  end

  # The merge stamps one source on everything it writes, but these titles are
  # coming *back* from the record — they keep whatever source they already
  # had, or the timeline would claim the operator typed a provider's name.
  defp restore_sources(merged, markers) do
    by_title = Map.new(markers, &{&1.title, &1.title_source})

    Enum.map(merged, fn chapter ->
      %{chapter | title_source: Map.get(by_title, chapter.title, chapter.title_source)}
    end)
  end

  defp read(media) do
    with {:ok, paths} <- Scanner.audio_files(media),
         {:ok, probes} <- Scanner.probe_all(paths) do
      {chapters, marker_source} = Scanner.chapters(probes)
      %{chapters: chapters, marker_source: marker_source, files: length(paths)}
    else
      {:error, reason} -> raise "Couldn't read the files: #{inspect(reason)}"
    end
  end

  defp message(%{message: message}), do: message
  defp message(exception), do: inspect(exception)
end
