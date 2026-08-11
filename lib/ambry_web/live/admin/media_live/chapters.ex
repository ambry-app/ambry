defmodule AmbryWeb.Admin.MediaLive.Chapters do
  @moduledoc """
  The chapter editor: markers on the left, titles on the right.

  The two columns are the whole point. A **marker** is a position and is only
  meaningful against the actual bytes — provider chapter times describe their
  own retail edition and drift by minutes across a book — so markers come
  from the files and nothing else may write them. A **title** is just a name,
  so it comes from wherever the best one is, per row, and the import doors
  above the list are title sources rather than chapter sources.

  See the roadmap's 1h, and `Ambry.Media.Chapters.Merge` for how a title list
  that doesn't line up gets poured on anyway.
  """
  use AmbryWeb, :admin_live_view

  import AmbryWeb.Admin.MediaLive.Chapters.Preview,
    only: [marker_source_phrase: 1, timecode: 1, title_source_label: 1, title_summary: 1]

  alias Ambry.Media
  alias Ambry.Media.Media.Chapter
  alias AmbryWeb.Admin.MediaLive.Chapters.AudibleImportForm
  alias AmbryWeb.Admin.MediaLive.Chapters.SourceImportForm
  alias Ecto.Changeset

  @impl Phoenix.LiveView
  def mount(%{"id" => id}, _session, socket) do
    media = Media.get_media!(id)
    changeset = Media.change_media(media, %{})

    {:ok,
     socket
     |> assign_form(changeset)
     |> assign(
       page_title: "#{Ambry.Media.Media.display_title(media)} - Chapters",
       media: media,
       import: nil
     )}
  end

  @impl Phoenix.LiveView
  def handle_params(%{"import" => type}, _url, socket) do
    {:noreply, assign(socket, import: import_assigns(socket, type))}
  end

  def handle_params(_params, _url, socket) do
    {:noreply, assign(socket, import: nil)}
  end

  @impl Phoenix.LiveView
  def handle_event("validate", %{"media" => media_params}, socket) do
    changeset =
      socket.assigns.media
      |> Media.change_media(mark_typed_titles(media_params, socket))
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("submit", %{"media" => media_params}, socket) do
    media_params = mark_typed_titles(media_params, socket)

    case Media.update_media(socket.assigns.media, media_params) do
      {:ok, media} ->
        {:noreply,
         socket
         |> put_flash(:info, "Updated chapters for #{media.book.title}")
         |> push_navigate(to: ~p"/admin/media")}

      {:error, %Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  def handle_event("open-import-form", %{"type" => type}, socket) do
    {:noreply, assign(socket, import: import_assigns(socket, type))}
  end

  @impl Phoenix.LiveView
  def handle_info({:chapters, chapters, marker_source}, socket) do
    params =
      socket.assigns.form.params
      |> Map.put("chapters", Enum.map(chapters, &chapter_params/1))
      |> put_marker_source(marker_source)

    changeset = Media.change_media(socket.assigns.media, params)

    {:noreply, socket |> assign_form(changeset) |> assign(import: nil)}
  end

  # An import replaces the whole list, so the sort param that was tracking
  # the old rows would re-order the new ones against positions that no longer
  # exist.
  defp chapter_params(chapter) do
    %{
      "time" => to_string(chapter.time),
      "title" => chapter.title,
      "title_source" => chapter.title_source && to_string(chapter.title_source)
    }
  end

  # A titles merge says nothing about where the markers came from — that is
  # the entire distinction this page is built on — so it leaves the recorded
  # source alone rather than writing a fresh one.
  defp put_marker_source(params, nil), do: params

  defp put_marker_source(params, source),
    do: Map.put(params, "chapter_marker_source", to_string(source))

  # Typing over a title is an answer, and an answer has to survive the next
  # merge — which it only does if it stops claiming a source that would let
  # the merge overwrite it.
  #
  # The comparison belongs here rather than in the changeset because a
  # chapter is an embed with no primary key: Ecto replaces the whole list on
  # every cast, so at the schema level *every* title looks like a change from
  # nil and there is nothing to compare against. What the operator just
  # edited is only knowable against what the form was showing them, which is
  # exactly what this has.
  defp mark_typed_titles(%{"chapters" => chapters} = params, socket) when is_map(chapters) do
    showing = socket |> current_chapters() |> List.to_tuple()

    Map.put(
      params,
      "chapters",
      Map.new(chapters, fn {index, chapter} ->
        {index, mark_typed(chapter, at(showing, index))}
      end)
    )
  end

  defp mark_typed_titles(params, _socket), do: params

  defp mark_typed(chapter, nil), do: chapter

  defp mark_typed(chapter, showing) do
    # An explicitly changed source is somebody answering deliberately (an
    # import, or the renumbering below); only a title that moved on its own
    # is the operator typing.
    if chapter["title"] != showing.title and
         chapter["title_source"] == to_string(showing.title_source) do
      Map.put(chapter, "title_source", "manual")
    else
      chapter
    end
  end

  defp at(showing, index) do
    case Integer.parse(index) do
      {index, ""} when index < tuple_size(showing) -> elem(showing, index)
      _out_of_range_or_not_an_index -> nil
    end
  end

  # The modals merge against what is on screen, not what is in the database:
  # an operator who has just nudged three markers and not saved yet means
  # those markers, and pouring titles onto the stale ones would silently undo
  # the nudge.
  defp import_assigns(socket, type) do
    %{
      type: String.to_existing_atom(type),
      query: socket.assigns.media.book.title,
      markers: current_chapters(socket)
    }
  end

  defp current_chapters(socket) do
    socket.assigns.form.source |> Changeset.apply_changes() |> Map.fetch!(:chapters)
  end

  # The generated floor is a *position*, so it has to stop saying "Chapter 7"
  # the moment a row is inserted above it. Titles anybody chose — typed, or
  # accepted from a provider — are left exactly where they are, which is the
  # whole reason `:generated` is tracked separately from every other source.
  #
  # This also gives a freshly-added blank row a title, so adding one doesn't
  # greet the operator with a validation error on a field they were about to
  # get to anyway.
  defp assign_form(socket, %Changeset{} = changeset) do
    assign(socket, :form, changeset |> renumber_generated() |> to_form())
  end

  defp renumber_generated(changeset) do
    case Changeset.get_change(changeset, :chapters) do
      nil ->
        changeset

      chapters ->
        Changeset.put_change(changeset, :chapters, renumber(chapters))
    end
  end

  defp renumber(chapters) do
    chapters
    # A dropped row is still in the list, marked for deletion; numbering
    # around it would leave a gap the operator never asked for.
    |> Enum.reduce({[], 0}, fn chapter, {acc, index} ->
      if chapter.action == :replace do
        {[chapter | acc], index}
      else
        {[maybe_generate_title(chapter, index) | acc], index + 1}
      end
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  defp maybe_generate_title(chapter, index) do
    title = Changeset.get_field(chapter, :title)
    source = Changeset.get_field(chapter, :title_source)

    if blank?(title) or source == :generated do
      chapter
      |> Changeset.put_change(:title, Chapter.generated_title(index))
      |> Changeset.put_change(:title_source, :generated)
    else
      chapter
    end
  end

  defp blank?(nil), do: true
  defp blank?(title) when is_binary(title), do: String.trim(title) == ""

  defp import_form(:source), do: SourceImportForm
  defp import_form(:audible), do: AudibleImportForm

  defp open_import_form(media, type),
    do: JS.patch(~p"/admin/media/#{media}/chapters?import=#{type}")

  defp close_import_form(media), do: JS.patch(~p"/admin/media/#{media}/chapters", replace: true)

  # What the list is made of right now, for the header — read off the form so
  # it follows unsaved edits.
  defp chapters(form) do
    form.source |> Changeset.apply_changes() |> Map.fetch!(:chapters)
  end

  defp marker_source(form) do
    form.source |> Changeset.apply_changes() |> Map.fetch!(:chapter_marker_source)
  end
end
