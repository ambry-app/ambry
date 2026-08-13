defmodule AmbryWeb.Admin.MediaLive.Form do
  @moduledoc """
  The media form, curated the import form's way — see `AmbryWeb.Admin.BookLive.Form`;
  this is the same model at the recording level (narrators, square cover
  art, publisher, publication facts).
  """
  use AmbryWeb, :admin_live_view

  import Ambry.Paths
  import AmbryWeb.Admin.ChapterEditor
  import AmbryWeb.Admin.Curation
  import AmbryWeb.Admin.ParamHelpers
  import AmbryWeb.Admin.UploadHelpers

  alias Ambry.Inbox
  alias Ambry.Media
  alias Ambry.Media.Chapters.Merge
  alias Ambry.Metadata.Provider
  alias Ambry.Metadata.Registry
  alias Ambry.Metadata.Search, as: MetadataSearch
  alias Ambry.People
  alias Ambry.People.Person
  alias AmbryWeb.Admin.Evidence
  alias AmbryWeb.Admin.MediaLive.Form.FileBrowser
  alias AmbryWeb.Admin.ProvenanceHints
  alias AmbryWeb.Admin.Reordering
  alias Ecto.Changeset
  alias Phoenix.LiveView.AsyncResult

  @scalar_kinds %{
    "published" => :published,
    "publisher" => :publisher,
    "description" => :description,
    "image" => :image
  }

  @impl Phoenix.LiveView
  def mount(params, _session, socket) do
    {:ok,
     socket
     |> allow_image_upload(:image)
     |> allow_audio_upload(:audio)
     |> allow_supplemental_file_upload(:supplemental)
     |> assign(
       retrying: nil,
       chips: %{},
       chapter_import: nil,
       chapters_applied_asin: nil,
       provenance_hints: %{},
       select_files: false,
       selected_files: MapSet.new(),
       source_files_expanded: false,
       narrators: People.narrators_for_select(),
       books: Ambry.Books.books_for_select(),
       local_import_path: Ambry.Paths.local_import_path()
     )
     |> apply_action(socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    media = Media.get_media!(id)

    changeset =
      Media.change_media(
        media,
        %{"image_type" => "upload", "source_type" => default_source_type(socket)}
      )

    socket
    |> assign_form(changeset)
    |> assign(
      page_title: Media.Media.display_title(media),
      media: media,
      recording_groups: Media.recording_groups_for_select(media.book_id),
      file_stats: Media.get_media_file_details(media),
      # View state, not derived per render: deriving it from the typeahead's
      # value made the row vanish mid-edit the moment the box was cleared.
      group_row_visible: media.recording_group_id != nil or media.part_number != nil
    )
    |> assign(
      evidence:
        Evidence.new(seed_fields(media, socket.assigns), known: Evidence.known_from(media))
    )
  end

  defp apply_action(socket, :new, _params) do
    media = %Media.Media{media_narrators: []}

    changeset =
      Media.change_media(
        media,
        %{"image_type" => "upload", "source_type" => default_source_type(socket)}
      )

    socket
    |> assign_form(changeset)
    |> assign(
      page_title: "New Audiobook",
      media: media,
      recording_groups: [],
      file_stats: nil,
      group_row_visible: false
    )
    |> assign(evidence: Evidence.new(%{}))
  end

  # The search the recording itself suggests: its book's title and author, and
  # its first narrator — the field that tells two recordings of one work apart.
  #
  # The author is not optional. Without it the recording search is a bare
  # title, and a bare title is how "The Martian" comes back as study guides
  # and conversation starters: Audible's catalog takes `author` as a real
  # parameter, and the scorer needs it to tell a content farm's companion work
  # from the book.
  defp seed_fields(media, assigns) do
    books = Map.new(assigns.books, &{&1.id, &1.label})
    narrators = Map.new(assigns.narrators, &{&1.id, &1.label})

    narrator =
      case media.media_narrators do
        [%{narrator_id: narrator_id} | _rest] -> narrators[narrator_id]
        _empty -> nil
      end

    %{
      "title" => books[media.book_id],
      "author" => first_author(assigns.books, media.book_id),
      "narrator" => narrator
    }
  end

  # The large thumbnail when it is a thumbnail *of this image* — a freshly
  # chosen one hasn't been derived yet, and the saved record's thumbnails
  # still describe the picture it is replacing.
  defp preview_src(media, image_path) do
    if media.thumbnails && image_path == media.image_path,
      do: media.thumbnails.large,
      else: image_path
  end

  # `books_for_select`'s `detail` is the book's author names, comma-joined for
  # display. One name, like the inbox's own hints: a query naming every author
  # of a collaboration matches nothing at a storefront.
  defp first_author(books, book_id) do
    case Enum.find(books, &(&1.id == book_id)) do
      %{detail: detail} when is_binary(detail) ->
        detail |> String.split(",") |> hd() |> String.trim()

      _none ->
        nil
    end
  end

  defp default_source_type(socket) do
    if socket.assigns.local_import_path do
      "local_import"
    else
      "upload"
    end
  end

  @impl Phoenix.LiveView
  def handle_params(%{"browse" => _}, _url, socket) do
    {:noreply, assign(socket, select_files: true)}
  end

  def handle_params(_params, _url, socket) do
    {:noreply, assign(socket, select_files: false)}
  end

  @impl Phoenix.LiveView
  def handle_event("validate", %{"media" => media_params}, socket) do
    socket =
      if media_params["image_type"] == "upload" do
        socket
      else
        cancel_all_uploads(socket, :image)
      end

    media_params = mark_typed_titles(media_params, current_chapters(socket.assigns.form))

    changeset =
      socket.assigns.media
      |> Media.change_media(media_params)
      |> Map.put(:action, :validate)

    {:noreply,
     socket
     |> assign_form(changeset)
     |> assign(
       # groups follow the chosen book — a set belongs to one book
       recording_groups: Media.recording_groups_for_select(media_params["book_id"]),
       provenance_hints: ProvenanceHints.prune(socket.assigns.provenance_hints, media_params)
     )
     |> refresh_chips()}
  end

  def handle_event("submit", %{"media" => media_params}, socket) do
    media_params = mark_typed_titles(media_params, current_chapters(socket.assigns.form))

    socket =
      assign(socket,
        provenance_hints: ProvenanceHints.prune(socket.assigns.provenance_hints, media_params)
      )

    with :ok <- changeset_valid?(socket, media_params),
         {:ok, media_params} <- handle_image_upload(socket, media_params, :image),
         {:ok, media_params} <-
           handle_image_import(media_params["image_import_url"], media_params),
         {:ok, media_params} <-
           handle_supplemental_files_upload(socket, media_params, :supplemental),
         {:ok, media_params} <- handle_audio_files_upload(socket, media_params, :audio),
         {:ok, media_params} <- handle_audio_files_import(socket, media_params) do
      save_media(socket, socket.assigns.live_action, media_params)
    else
      {:error, %Changeset{} = changeset} -> {:noreply, assign_form(socket, changeset)}
      {:error, :failed_upload} -> {:noreply, put_flash(socket, :error, "Failed to upload image")}
      {:error, :failed_import} -> {:noreply, put_flash(socket, :error, "Failed to import image")}
    end
  end

  def handle_event("move", params, socket) do
    changeset = socket.assigns.form.source
    media_params = Reordering.move(changeset, socket.assigns.form.params, params)

    {:noreply, assign_form(socket, Media.change_media(socket.assigns.media, media_params))}
  end

  def handle_event("cancel-upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :audio, ref)}
  end

  # ── the part set ───────────────────────────────────────────────────────

  def handle_event("add-group-row", _params, socket) do
    {:noreply, assign(socket, group_row_visible: true)}
  end

  def handle_event("remove-group-row", _params, socket) do
    params =
      Map.merge(socket.assigns.form.params, %{"recording_group_id" => "", "part_number" => ""})

    {:noreply,
     socket
     |> assign_form(Media.change_media(socket.assigns.media, params))
     |> assign(group_row_visible: false)}
  end

  def handle_event("cancel-supplemental-upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :supplemental, ref)}
  end

  # ── chapters ───────────────────────────────────────────────────────────
  #
  # The title import, inline where a modal used to be: the fetched titles
  # render into the rows as a proposed column, and nothing lands until
  # Take — Save is still the only thing that persists.

  def handle_event("fetch-chapter-titles", %{"asin" => asin}, socket) do
    chip =
      socket.assigns.evidence
      |> Evidence.used_records()
      |> title_chips(socket.assigns.chapters_applied_asin)
      |> Enum.find(&(&1.asin == asin))

    if chip do
      {:noreply,
       socket
       |> assign(chapter_import: pending_import(chip))
       |> start_async(:chapter_titles, fn -> fetch_chapter_titles(asin) end)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("apply-chapter-titles", _params, socket) do
    # against the on-screen markers, not the stored ones — an unsaved nudge
    # means those markers
    showing = current_chapters(socket.assigns.form)

    with %{chip: chip, result: %AsyncResult{ok?: true, result: fetched}} <-
           socket.assigns.chapter_import,
         # one-to-one or not at all — an operator call; a mismatched list
         # stays visible in the proposed column but is never poured
         true <- takeable?(fetched.incoming, showing) do
      {merged, _alignment} = Merge.titles(showing, fetched.incoming, :provider)

      {:noreply,
       socket
       |> put_chapters(merged)
       |> assign(
         chapter_import: nil,
         chapters_applied_asin: chip.asin,
         provenance_hints:
           ProvenanceHints.for_list(socket.assigns.provenance_hints, "chapters", fetched.source)
       )}
    else
      _not_takeable -> {:noreply, socket}
    end
  end

  def handle_event("cancel-chapter-import", _params, socket) do
    {:noreply, assign(socket, chapter_import: nil)}
  end

  # ── the evidence panel ─────────────────────────────────────────────────

  def handle_event("research", params, socket) do
    fields = Map.take(params, ["title", "author", "narrator"])
    query = Provider.Query.from_fields(fields)

    if Provider.Query.blank?(query) do
      {:noreply, socket}
    else
      hints =
        Inbox.form_hints(%{
          title: params["title"],
          author: params["author"],
          narrator: params["narrator"]
        })

      {:noreply,
       socket
       |> assign(evidence: Evidence.begin(socket.assigns.evidence, fields))
       |> start_async(:evidence_search, fn -> recording_fan_out(query, hints) end)}
    end
  end

  def handle_event("retry-provider", %{"provider" => provider_id}, socket) do
    query = Provider.Query.from_fields(socket.assigns.evidence.fields)

    with false <- Provider.Query.blank?(query),
         {:ok, entry} <- Registry.fetch(provider_id) do
      hints =
        Inbox.form_hints(
          Map.new(socket.assigns.evidence.fields, fn {k, v} -> {String.to_existing_atom(k), v} end)
        )

      {:noreply,
       socket
       |> assign(retrying: provider_id)
       |> start_async(:evidence_search, fn ->
         {books, outcome} = MetadataSearch.books_one(entry, query)
         {Inbox.score_records(books, entry, hints), [outcome]}
       end)}
    else
      _no -> {:noreply, socket}
    end
  end

  def handle_event("toggle-evidence", %{"source" => source, "id" => id}, socket) do
    {:noreply,
     socket
     |> assign(evidence: Evidence.toggle(socket.assigns.evidence, source, id))
     |> refresh_chips()}
  end

  def handle_event("accept-proposal", %{"field" => field, "key" => key}, socket) do
    with {:ok, kind} <- Map.fetch(@scalar_kinds, field),
         %{} = proposal <- Evidence.find_proposal(socket.assigns.evidence, kind, key) do
      hints = ProvenanceHints.from_import(proposal.params, proposal.source, proposal.record)
      new_params = Map.merge(socket.assigns.form.params, proposal.params)
      changeset = Media.change_media(socket.assigns.media, new_params)

      {:noreply,
       socket
       |> assign_form(changeset)
       |> assign(provenance_hints: Map.merge(socket.assigns.provenance_hints, hints))
       |> refresh_chips()}
    else
      _missing -> {:noreply, socket}
    end
  end

  def handle_event("accept-entity", %{"field" => "narrators", "key" => key}, socket) do
    case Evidence.find_proposal(socket.assigns.evidence, :narrators, key) do
      %{} = proposal ->
        narrator_id = resolve_narrator(proposal.params["name"], proposal.source)

        {:noreply,
         socket
         |> append_narrator_row(narrator_id)
         |> assign(
           narrators: People.narrators_for_select(),
           provenance_hints:
             ProvenanceHints.for_list(
               socket.assigns.provenance_hints,
               "media_narrators",
               proposal.source
             )
         )
         |> refresh_chips()}

      _missing ->
        {:noreply, socket}
    end
  end

  # The recording level asks two ways, like the import form: Audible's catalog
  # directly, and the editions the work-level databases keep — the route to a
  # recording no storefront will admit exists.
  #
  # **Only recordings are listed.** Mixing the work records in gave the
  # operator a description to choose, and cost more than it bought: a work
  # record renders "The Martian — Andy Weir · 2011 · Hardcover", which is also
  # what four of its editions render, so the list stopped being a list of
  # readings. The editions carry the book's description themselves now (see
  # `Hardcover.editions/2`), which is the same text by a shorter road.
  #
  # The work search still runs, because its records are the ids the editions
  # are fetched by. Only its **failures** are reported: a chip saying
  # "Hardcover: 9" would describe a search whose records aren't shown, but a
  # work provider that was down took its editions with it, and that has to be
  # visible or the recordings list is short for no stated reason.
  defp recording_fan_out(query, hints) do
    {audible_found, audible_outcomes} = MetadataSearch.books(query, level: :recording)

    audible_records =
      Enum.flat_map(audible_found, fn {entry, books} ->
        Inbox.score_records(books, entry, hints)
      end)

    {work_found, work_outcomes} = MetadataSearch.books(query, level: :work)

    work_records =
      Enum.flat_map(work_found, fn {entry, books} -> Inbox.score_records(books, entry, hints) end)

    # Only the top group gets asked for editions. Every work record used to,
    # which on The Martian meant nine editions calls and nine "Hardcover
    # editions" chips, seven of them reporting zero.
    {edition_records, edition_outcomes} =
      work_records |> Inbox.top_group() |> Inbox.editions_of(hints)

    {audible_records ++ edition_records,
     audible_outcomes ++
       edition_outcomes ++ Enum.filter(work_outcomes, &(&1["status"] == "failed"))}
  end

  @impl Phoenix.LiveView
  def handle_async(:evidence_search, {:ok, result}, socket) do
    {:noreply,
     socket
     |> assign(evidence: Evidence.absorb(socket.assigns.evidence, result), retrying: nil)
     |> refresh_chips()}
  end

  def handle_async(:evidence_search, {:exit, _reason}, socket) do
    {:noreply,
     socket
     |> assign(evidence: %{socket.assigns.evidence | running?: false}, retrying: nil)
     |> put_flash(:error, "Searching the providers failed. Try again.")}
  end

  def handle_async(:chapter_titles, {:ok, fetched}, socket) do
    {:noreply, update_pending_import(socket, &AsyncResult.ok(&1, fetched))}
  end

  def handle_async(:chapter_titles, {:exit, reason}, socket) do
    {:noreply, update_pending_import(socket, &AsyncResult.failed(&1, async_fail(reason)))}
  end

  # A titles merge changed no marker, so the recorded marker source stands —
  # claiming otherwise would put a provider's name on a timeline it never
  # touched.
  defp put_chapters(socket, chapters) do
    params =
      socket.assigns.form.params
      # An import replaces the whole list; a sort param tracking the old rows
      # would re-order the new ones against positions that no longer exist.
      |> Map.drop(["chapters_sort", "chapters_drop"])
      |> Map.put("chapters", Enum.map(chapters, &chapter_params/1))

    assign_form(socket, Media.change_media(socket.assigns.media, params))
  end

  # The narrator identity a proposed credit names — an existing narrator of
  # that name, the identity added to an existing person, or a new person.
  defp resolve_narrator(name, source) do
    case Ambry.Search.find_first(name, Person) do
      nil ->
        {:ok, %{narrators: [narrator]}} =
          People.create_person(
            %{name: name, narrators: [%{name: name}]},
            provenance: %{"name" => source}
          )

        narrator.id

      %Person{narrators: []} = person ->
        {:ok, %{narrators: [narrator]}} =
          People.update_person(person, %{narrators: [%{name: person.name}]})

        narrator.id

      %Person{narrators: narrators} ->
        credited =
          Enum.find(narrators, &(String.downcase(&1.name) == String.downcase(name))) ||
            List.first(narrators)

        credited.id
    end
  end

  defp append_narrator_row(socket, narrator_id) do
    changeset = socket.assigns.form.source

    rows =
      changeset
      |> Changeset.get_field(:media_narrators)
      |> Enum.map(fn row ->
        base = if row.id, do: %{"id" => to_string(row.id)}, else: %{}
        Map.put(base, "narrator_id", to_string(row.narrator_id))
      end)

    params =
      socket.assigns.form.params
      |> Map.drop(["media_narrators_sort", "media_narrators_drop"])
      |> Map.put("media_narrators", rows ++ [%{"narrator_id" => to_string(narrator_id)}])

    assign_form(socket, Media.change_media(socket.assigns.media, params))
  end

  defp refresh_chips(socket) do
    %{evidence: evidence, form: form} = socket.assigns

    chips =
      if evidence && Evidence.any_used?(evidence) do
        %{
          published:
            evidence
            |> Evidence.proposals(:published)
            |> mark_chosen(%{
              "published" => Changeset.get_field(form.source, :published),
              "published_format" => Changeset.get_field(form.source, :published_format)
            }),
          publisher:
            evidence
            |> Evidence.proposals(:publisher)
            |> mark_chosen(%{"publisher" => Changeset.get_field(form.source, :publisher)}),
          description:
            evidence
            |> Evidence.proposals(:description)
            |> mark_chosen(%{"description" => Changeset.get_field(form.source, :description)}),
          image:
            evidence
            |> Evidence.proposals(:image)
            |> mark_chosen(%{
              "image_type" => Changeset.get_field(form.source, :image_type),
              "image_import_url" => Changeset.get_field(form.source, :image_import_url)
            }),
          narrators:
            evidence
            |> Evidence.proposals(:narrators)
            |> mark_present(current_narrator_names(form.source, socket.assigns.narrators))
        }
      else
        %{}
      end

    assign(socket, chips: chips)
  end

  defp current_narrator_names(changeset, options) do
    labels = Map.new(options, &{&1.id, &1.label})

    changeset
    |> Changeset.get_field(:media_narrators)
    |> Enum.map(&labels[&1.narrator_id])
    |> Enum.reject(&is_nil/1)
  end

  @impl Phoenix.LiveView
  def handle_info({:files_selected, files}, socket) do
    {:noreply,
     socket
     |> assign(selected_files: files)
     |> push_patch(to: media_path(socket.assigns.media), replace: true)}
  end

  defp cancel_all_uploads(socket, upload) do
    Enum.reduce(socket.assigns.uploads[upload].entries, socket, fn entry, socket ->
      cancel_upload(socket, upload, entry.ref)
    end)
  end

  defp handle_supplemental_files_upload(socket, media_params, name) do
    uploaded_supplemental_files_params = consume_uploaded_supplemental_files(socket, name)

    {:ok,
     media_params
     |> Map.put_new("supplemental_files", [])
     |> Map.update!("supplemental_files", fn files_params ->
       map_to_list(files_params) ++ uploaded_supplemental_files_params
     end)}
  end

  defp handle_audio_files_upload(socket, %{"source_type" => "upload"} = media_params, name) do
    folder_id = Media.Media.source_id(socket.assigns.media)
    source_folder = source_media_disk_path(folder_id)

    audio_files =
      consume_uploaded_entries(socket, name, fn %{path: path}, entry ->
        File.mkdir_p!(source_folder)

        dest = Path.join([source_folder, entry.client_name])
        File.cp!(path, dest)

        {:ok, dest}
      end)

    existing_source_files = socket.assigns.media.source_files

    media_params =
      if audio_files == [] do
        media_params
      else
        Map.merge(media_params, %{
          "source_path" => source_folder,
          "source_files" => Enum.sort(existing_source_files ++ audio_files, NaturalOrder)
        })
      end

    {:ok, media_params}
  end

  defp handle_audio_files_upload(_socket, media_params, _name) do
    {:ok, media_params}
  end

  defp handle_audio_files_import(socket, %{"source_type" => "local_import"} = media_params) do
    folder_id = Media.Media.source_id(socket.assigns.media)
    source_folder = source_media_disk_path(folder_id)

    existing_source_files = socket.assigns.media.source_files
    selected_files = Enum.to_list(socket.assigns.selected_files)
    new_source_files = Enum.sort(existing_source_files ++ selected_files, NaturalOrder)

    {:ok,
     Map.merge(media_params, %{
       "source_path" => source_folder,
       "source_files" => new_source_files
     })}
  end

  defp handle_audio_files_import(_socket, media_params) do
    {:ok, media_params}
  end

  defp changeset_valid?(socket, media_params) do
    case Media.change_media(socket.assigns.media, media_params) do
      %{valid?: true} -> :ok
      # if the _only_ error is the missing source-path, then we let it pass (at first)
      %{errors: [source_path: {"can't be blank", [validation: :required]}]} -> :ok
      %Changeset{} = changeset -> {:error, Map.put(changeset, :action, :validate)}
    end
  end

  defp handle_image_upload(socket, media_params, name) do
    case consume_uploaded_image(socket, name) do
      {:ok, :no_file} -> {:ok, media_params}
      {:ok, path} -> {:ok, Map.put(media_params, "image_path", path)}
      {:error, _reason} -> {:error, :failed_upload}
    end
  end

  defp handle_image_import(url, media_params) do
    case handle_image_import(url) do
      {:ok, :no_image_url} -> {:ok, media_params}
      {:ok, path} -> {:ok, Map.put(media_params, "image_path", path)}
      {:error, _reason} -> {:error, :failed_import}
    end
  end

  defp save_media(socket, :edit, media_params) do
    opts = [provenance: ProvenanceHints.sources(socket.assigns.provenance_hints)]

    case Media.update_media(socket.assigns.media, media_params, opts) do
      {:ok, media} ->
        maybe_start_processor!(media, media_params, :edit)
        # a title override or a changed date moves the folder
        {:ok, _job} = Media.organize_async(media)

        {:noreply,
         socket
         |> put_flash(:info, "Updated audiobook for #{media.book.title}")
         |> push_navigate(to: ~p"/admin/audiobooks")}

      {:error, %Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save_media(socket, :new, media_params) do
    opts = [provenance: ProvenanceHints.sources(socket.assigns.provenance_hints)]

    case Media.create_media(media_params, opts) do
      {:ok, media} ->
        media = Media.get_media!(media.id)
        maybe_start_processor!(media, media_params, :new)

        {:noreply,
         socket
         |> put_flash(:info, "Created new audiobook for #{media.book.title}")
         |> push_navigate(to: ~p"/admin/audiobooks")}

      {:error, %Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp assign_form(socket, %Changeset{} = changeset) do
    # generated chapter titles are positions and follow their rows
    changeset = renumber_generated(changeset)

    assign(socket,
      form: to_form(changeset),
      # the move buttons need to know where the ends of the list are
      media_narrator_count: length(Changeset.get_assoc(changeset, :media_narrators))
    )
  end

  defp maybe_start_processor!(media, media_params, :new) do
    processor =
      case parse_requested_processor(media_params["processor"]) do
        :none_specified -> :auto
        processor -> processor
      end

    Media.run_processor_async(media, processor)
  end

  defp maybe_start_processor!(media, media_params, :edit) do
    case parse_requested_processor(media_params["processor"]) do
      :none_specified ->
        :noop

      processor ->
        Media.run_processor_async(media, processor)
    end
  end

  defp processors(%Media.Media{source_path: path} = media, [_ | _] = uploads)
       when is_binary(path) do
    filenames = Enum.map(uploads, & &1.client_name)
    {media, filenames} |> Media.available_processors() |> Enum.map(&{&1.name(), &1})
  end

  defp processors(_media, [_ | _] = uploads) do
    filenames = Enum.map(uploads, & &1.client_name)
    filenames |> Media.available_processors() |> Enum.map(&{&1.name(), &1})
  end

  defp processors(%Media.Media{source_path: path} = media, _uploads) when is_binary(path) do
    media |> Media.available_processors() |> Enum.map(&{&1.name(), &1})
  end

  defp processors(_media, _uploads), do: []

  defp parse_requested_processor(""), do: :none_specified
  defp parse_requested_processor(string), do: String.to_existing_atom(string)

  # Components

  attr :file, :any, required: true
  attr :label, :string, required: true
  attr :error_type, :atom, default: :error
  attr :class, :string, default: nil

  defp file_stat_row(assigns) do
    ~H"""
    <div class={[@class]}>
      <div class="flex p-2">
        <div class="w-28 pr-2">
          <.badge color={:gray}>{@label}</.badge>
        </div>
        <%= if @file do %>
          <div class="grow break-all pr-2">
            {@file.path}
          </div>
          <div class="shrink">
            <%= case @file.stat do %>
              <% error when is_atom(error) -> %>
                <.badge color={color_for_error_type(@error_type)}>{error}</.badge>
              <% stat when is_map(stat) -> %>
                <.badge color={:gray}>{format_filesize(stat.size)}</.badge>
            <% end %>
          </div>
        <% else %>
          <div class="grow" />
          <div class="shrink">
            <.badge color={:red}>nil</.badge>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp color_for_error_type(:error), do: :red
  defp color_for_error_type(:warn), do: :yellow

  defp format_filesize(bytes) do
    Ambry.Utils.humanize_bytes(bytes)
  end

  defp preview_date_format(form) do
    format_published(%{
      published_format: Ecto.Changeset.get_field(form.source, :published_format),
      published: Ecto.Changeset.get_field(form.source, :published)
    })
  end

  defp media_path(media, params \\ %{})
  defp media_path(%Media.Media{id: nil}, params), do: ~p"/admin/audiobooks/new?#{params}"
  defp media_path(media, params), do: ~p"/admin/audiobooks/#{media}/edit?#{params}"

  defp open_file_browser(media), do: JS.patch(media_path(media, %{browse: :files}))
  defp close_modal(media), do: JS.patch(media_path(media), replace: true)
end
