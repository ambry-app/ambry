defmodule AmbryWeb.Admin.MediaLive.Form do
  @moduledoc """
  The media form, curated the import form's way — see `AmbryWeb.Admin.BookLive.Form`;
  this is the same model at the recording level (narrators, square cover
  art, publisher, publication facts).
  """
  use AmbryWeb, :admin_live_view

  import AmbryWeb.Admin.ChapterEditor
  import AmbryWeb.Admin.Curation
  import AmbryWeb.Admin.NewPerson, only: [new_person_card: 1]
  import AmbryWeb.Admin.ParamHelpers
  import AmbryWeb.Admin.UploadHelpers

  alias Ambry.Books
  alias Ambry.Images
  alias Ambry.Inbox
  alias Ambry.Media
  alias Ambry.Media.Chapters.Merge
  alias Ambry.Metadata.Outcome
  alias Ambry.Metadata.Provider
  alias Ambry.Metadata.Registry
  alias Ambry.Metadata.Search, as: MetadataSearch
  alias Ambry.People
  alias AmbryWeb.Admin.Evidence
  alias AmbryWeb.Admin.NewPerson
  alias AmbryWeb.Admin.ProvenanceHints
  alias AmbryWeb.Admin.Reordering
  alias AmbryWeb.Admin.ReturnTo
  alias AmbryWeb.Admin.Revert
  alias Ecto.Changeset
  alias Phoenix.LiveView.AsyncResult

  # The trio that carries a chosen cover through the form: two say where it
  # comes from and the third is the one being replaced.
  @image_params ~w(image_type image_import_url image_path)

  @scalar_kinds %{
    "title" => :title,
    "published" => :published,
    "publisher" => :publisher,
    "description" => :description,
    "image" => :image
  }

  # Credits, which are people: accepting one of these stages a row naming the
  # human, and the save makes them (`Ambry.Ecto.EntityRef`).
  @entity_kinds %{"narrators" => :narrators}
  @person_events NewPerson.events()

  @impl Phoenix.LiveView
  def mount(params, _session, socket) do
    {:ok,
     socket
     |> allow_image_upload(:image)
     |> allow_supplemental_file_upload(:supplemental)
     |> assign(
       retrying: nil,
       chips: %{},
       reverts: %{},
       chapter_import: nil,
       chapters_applied_asin: nil,
       file_chapters: %{chosen: false, running: false, label: "re-read the timestamps and titles"},
       provenance_hints: %{}
     )
     # The list the operator came from, kept so every way out of this form
     # goes back to it. See `AmbryWeb.Admin.ReturnTo`.
     |> assign(list_params: ReturnTo.list_params(params))
     |> NewPerson.mount()
     |> apply_action(socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    media = Media.get_media!(id)

    changeset = Media.change_media(media, %{"image_type" => "upload"})

    socket
    |> assign_form(changeset)
    |> assign(
      page_title: Media.Media.display_title(media),
      media: media,
      audio_files: audio_files(media),
      file_stats: legacy_file_stats(media),
      # View state, not derived per render: deriving it from the typeahead's
      # value made the row vanish mid-edit the moment the box was cleared.
      group_row_visible: media.recording_group_id != nil or media.part_number != nil
    )
    |> assign_book(media.book_id)
    |> assign(evidence: Evidence.new(seed_fields(media), known: Evidence.known_from(media)))
  end

  # What the recording is played from, in play order, in the stored form the
  # database holds — root-relative, or `/uploads/...` for a track outside
  # every root. A transcoded recording has no tracks: it plays the packaged
  # artifacts the fold below describes, beside the sources they were made
  # from.
  defp audio_files(%{media_tracks: tracks}),
    do: tracks |> Enum.sort_by(& &1.index) |> Enum.map(& &1.path)

  # Only a transcoded recording has streaming files, and only it pays for
  # the `File.ls` and four `File.stat`s that describe them.
  defp legacy_file_stats(%{media_tracks: [_ | _]}), do: nil
  defp legacy_file_stats(media), do: Media.get_media_file_details(media)

  # The search the recording itself suggests: its book's title and author, and
  # its first narrator — the field that tells two recordings of one work apart.
  #
  # The author is not optional. Without it the recording search is a bare
  # title, and a bare title is how "The Martian" comes back as study guides
  # and conversation starters: Audible's catalog takes `author` as a real
  # parameter, and the scorer needs it to tell a content farm's companion work
  # from the book.
  defp seed_fields(media) do
    book = Books.book_option(media.book_id)

    %{
      "title" => book && book.label,
      "author" => book && first_author(book),
      "narrator" => first_narrator(media)
    }
  end

  # The set drop-down is given its whole list up-front, so the list has to be
  # rebuilt whenever the book it belongs to changes.
  defp assign_book(socket, book_id) do
    assign(socket,
      book_id: book_id,
      recording_group_options: Media.recording_group_options(book_id)
    )
  end

  # The large thumbnail when it is a thumbnail *of this image* — a freshly
  # chosen one hasn't been derived yet, and the saved record's thumbnails
  # still describe the picture it is replacing.
  defp preview_src(media, image_path) do
    if media.thumbnails && image_path == media.image_path,
      do: media.thumbnails.large,
      else: image_path
  end

  # `Books.book_option/1`'s `detail` is the book's author names, comma-joined
  # for display. One name, like the inbox's own hints: a query naming every
  # author of a collaboration matches nothing at a storefront.
  defp first_author(%{detail: detail}) when is_binary(detail),
    do: detail |> String.split(",") |> hd() |> String.trim()

  defp first_author(_book), do: nil

  defp first_narrator(%{media_narrators: [%{narrator_id: id} | _rest]}) do
    case People.narrator_option(id) do
      %{label: label} -> label
      nil -> nil
    end
  end

  defp first_narrator(_media), do: nil

  @impl Phoenix.LiveView
  def handle_params(_params, _url, socket) do
    {:noreply, socket}
  end

  @impl Phoenix.LiveView
  def handle_event("validate", %{"media" => media_params}, socket) do
    socket =
      if media_params["image_type"] == "upload" do
        socket
      else
        cancel_all_uploads(socket, :image)
      end

    media_params =
      media_params
      |> mark_typed_titles(current_chapters(socket.assigns.form))
      |> naming_a_set(socket)

    changeset =
      socket.assigns.media
      |> Media.change_media(media_params)
      |> Map.put(:action, :validate)

    {:noreply,
     socket
     |> assign_form(changeset)
     # the set drop-down follows the chosen book — a set belongs to one book
     |> assign_book(media_params["book_id"])
     |> assign(
       provenance_hints: ProvenanceHints.prune(socket.assigns.provenance_hints, media_params)
     )
     |> refresh_chips()}
  end

  def handle_event("submit", %{"media" => media_params}, socket) do
    media_params =
      media_params
      |> mark_typed_titles(current_chapters(socket.assigns.form))
      |> naming_a_set(socket)

    socket =
      assign(socket,
        provenance_hints: ProvenanceHints.prune(socket.assigns.provenance_hints, media_params)
      )

    with :ok <- changeset_valid?(socket, media_params),
         {:ok, media_params} <- handle_image_upload(socket, media_params, :image),
         {:ok, media_params} <-
           handle_image_import(media_params["image_import_url"], media_params),
         {:ok, media_params} <- handle_embedded_image(socket, media_params),
         {:ok, media_params} <-
           handle_supplemental_files_upload(socket, media_params, :supplemental) do
      save_media(socket, socket.assigns.live_action, media_params)
    else
      {:error, %Changeset{} = changeset} -> {:noreply, assign_form(socket, changeset)}
      {:error, :failed_upload} -> {:noreply, put_flash(socket, :error, "Failed to upload image")}
      {:error, :failed_import} -> {:noreply, put_flash(socket, :error, "Failed to import image")}
    end
  end

  # ── the part set ───────────────────────────────────────────────────────

  def handle_event("add-group-row", _params, socket) do
    socket = assign(socket, group_row_visible: true)
    params = naming_a_set(socket.assigns.form.params, socket)

    {:noreply, assign_form(socket, Media.change_media(socket.assigns.media, params))}
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

  # The way back to the files, which the inbox has had all along and this
  # form did not: markers are file-derived facts, and a recording whose rows
  # are wrong had no way to say "read them again".
  #
  # It applies on arrival rather than previewing into the proposed column,
  # for the same reason the inbox's chip does: the column pairs one incoming
  # title to one existing marker, and re-reading the files is the one
  # proposal that can legitimately change how many markers there are. Nothing
  # is saved either way until Save.
  def handle_event("take-file-chapters", _params, socket) do
    media = socket.assigns.media

    {:noreply,
     socket
     |> assign(file_chapters: %{chosen: false, running: true}, chapter_import: nil)
     |> start_async(:file_chapters, fn -> read_file_chapters(media) end)}
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
       |> read_file_tags()
       |> start_async(:evidence_search, fn -> recording_fan_out(query, hints) end)}
    end
  end

  def handle_event("retry-provider", %{"provider" => outcome_id}, socket) do
    query = Provider.Query.from_fields(socket.assigns.evidence.fields)
    {provider_id, kind} = Outcome.split(outcome_id)

    with false <- Provider.Query.blank?(query),
         {:ok, entry} <- Registry.fetch(provider_id) do
      hints =
        Inbox.form_hints(
          Map.new(socket.assigns.evidence.fields, fn {k, v} -> {String.to_existing_atom(k), v} end)
        )

      {:noreply,
       socket
       |> assign(retrying: outcome_id)
       |> start_async(:evidence_search, fn -> retry_fan_out(entry, kind, query, hints) end)}
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

  # The way back out of a chip. Restores the field from the saved record and
  # drops the pending provenance with it: nothing was accepted after all, so
  # nothing should be recorded as accepted.
  def handle_event("revert-field", %{"field" => field}, socket) do
    case Map.fetch(@scalar_kinds, field) do
      {:ok, kind} ->
        params = Map.merge(socket.assigns.form.params, Revert.params(socket.assigns.media, kind))
        hints = Map.drop(socket.assigns.provenance_hints, [field, "image_path"])

        {:noreply,
         socket
         |> assign_form(Media.change_media(socket.assigns.media, params))
         |> assign(provenance_hints: hints)
         |> refresh_chips()}

      _unknown ->
        {:noreply, socket}
    end
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

  # A narrator a ticked record names, credited in one click.
  #
  # Two readings of one book differ by nothing but their narrators, so this is
  # the field a record most needs to be able to fill — and it was the only one
  # the form could not. It was here once and was removed (`17aa2234`) because
  # clicking a chip the recording already had credited them again; that is
  # `proposal_chip/1`'s business now, and `already_credited?/4` is the belt.
  # ── the people this form is about to create ────────────────────────────
  #
  # The card owns its own evidence and its own state; the form owns the
  # assign it lives in and nothing else.
  def handle_event(event, params, socket) when event in @person_events,
    do: NewPerson.handle_event(event, params, socket)

  def handle_event("accept-entity", %{"field" => field, "key" => key}, socket) do
    with {:ok, kind} <- Map.fetch(@entity_kinds, field),
         %{} = proposal <- Evidence.find_proposal(socket.assigns.evidence, kind, key) do
      {:noreply, accept_entity(socket, kind, proposal)}
    else
      _missing -> {:noreply, socket}
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
  # "Part of a set" with nothing chosen is the operator saying they mean a set
  # this book does not have yet, and the empty nested group is what makes the
  # name box render — the same idiom `Ambry.People.AuthorPerson` uses to open
  # a box for a pen name nobody has typed into. Only the form can say this: a
  # recording pointing at no group and holding no part number is simply not in
  # a set, and the schema cannot tell the two apart.
  defp naming_a_set(params, %{assigns: %{group_row_visible: true}}) do
    if params["recording_group_id"] in [nil, ""] do
      Map.put_new(params, "recording_group", %{})
    else
      Map.delete(params, "recording_group")
    end
  end

  defp naming_a_set(params, _not_in_a_set), do: Map.delete(params, "recording_group")

  defp retry_fan_out(entry, :search, query, hints) do
    {books, outcome} = MetadataSearch.books_one(entry, query)
    {Inbox.score_records(books, entry, hints), List.wrap(outcome)}
  end

  # The editions chip doesn't hang off a search anybody can re-run on its own:
  # editions are asked of a *work record*, so retrying one means finding this
  # provider's work records again and re-asking about those. Without this the
  # chip's id (`hardcover:editions`) simply missed the registry and the button
  # did nothing — visibly red, silently inert.
  defp retry_fan_out(entry, :editions, query, hints) do
    {found, _outcomes} = MetadataSearch.books(query, level: :work)

    found
    |> Enum.flat_map(fn {found_entry, books} ->
      Inbox.score_records(books, found_entry, hints)
    end)
    |> Enum.filter(&(&1["source"] == "provider:#{entry.id}"))
    |> Inbox.top_group()
    |> Inbox.editions_of(hints)
  end

  defp retry_fan_out(_entry, _kind, _query, _hints), do: {[], []}

  # The recording's own file is evidence too, and searching is when the
  # operator asked what else this recording could say about itself — so it is
  # when the file gets read, alongside the providers, rather than on every
  # page load. Reading it is an ffprobe against a NAS, and a form nobody came
  # to curate should not pay for one.
  #
  # Once only: the file does not change while the form is open, and a second
  # search must not cost a second probe.
  defp read_file_tags(%{assigns: %{evidence: %{tags: nil}, media: media}} = socket) do
    start_async(socket, :file_tags, fn -> Media.Scanner.tags(media) end)
  end

  defp read_file_tags(socket), do: socket

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
  def handle_async({:person_search, _key} = name, result, socket),
    do: NewPerson.handle_async(name, result, socket)

  def handle_async(:file_chapters, {:ok, {:ok, {[_row | _rest] = chapters, source}}}, socket) do
    {:noreply,
     socket
     |> put_file_chapters(chapters, source)
     |> assign(file_chapters: %{chosen: true, running: false})
     |> put_flash(:info, "Read #{length(chapters)} chapters from the files. Save to keep them.")}
  end

  # Files that carry no markers propose nothing. A chip that emptied rows the
  # operator typed by hand would be a destructive control wearing a
  # proposal's clothes.
  def handle_async(:file_chapters, {:ok, {:ok, {[], _source}}}, socket) do
    {:noreply,
     socket
     |> assign(file_chapters: %{chosen: false, running: false, label: "no markers in the files"})
     |> put_flash(:error, "These files carry no chapter markers. The rows are unchanged.")}
  end

  def handle_async(:file_chapters, _failed, socket) do
    {:noreply,
     socket
     |> assign(file_chapters: %{chosen: false, running: false})
     |> put_flash(:error, "Could not read this recording's files.")}
  end

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

  def handle_async(:file_tags, {:ok, {:ok, tags}}, socket) do
    evidence =
      Evidence.absorb_tags(socket.assigns.evidence, tags,
        embedded_cover_src: ~p"/admin/audiobooks/#{socket.assigns.media}/embedded-cover"
      )

    {:noreply, socket |> assign(evidence: evidence) |> refresh_chips()}
  end

  # A recording whose files have gone, or a container ffprobe won't read, has
  # nothing to say about itself. That is not an error worth a flash: the panel
  # simply holds one record fewer.
  def handle_async(:file_tags, _unreadable, socket), do: {:noreply, socket}

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

  # Every file, in play order — the same read the inbox does before an item
  # has a record, and an ffprobe apiece. That is why it happens on a click
  # and not on page load.
  defp read_file_chapters(media) do
    with {:ok, paths} <- Media.Scanner.audio_files(media),
         {:ok, probes} <- Media.Scanner.probe_all(paths) do
      {:ok, Media.Scanner.chapters(probes)}
    end
  end

  # A whole new list, markers and all — so the source line moves with it, and
  # any titles poured from an ASIN stop being what the rows hold.
  defp put_file_chapters(socket, chapters, source) do
    params = Map.put(socket.assigns.form.params, "chapter_marker_source", to_string(source))

    socket
    |> assign_form(Media.change_media(socket.assigns.media, params))
    |> put_chapters(chapters)
    |> assign(chapters_applied_asin: nil)
  end

  # The narrator identity a proposed credit names — an existing narrator of
  # that name, the identity added to an existing person, or a new person.
  # A chip stages the name; the person is made when the form is saved, in the
  # transaction that saves it. See the book form for why they used to differ.
  defp accept_entity(socket, :narrators, proposal) do
    name = proposal.params["name"]

    if credits_name?(
         socket.assigns.form.source,
         :media_narrators,
         :narrator_id,
         &People.narrator_option/1,
         :narrator,
         name
       ) do
      socket
    else
      params = append_row(socket.assigns.form, :media_narrators, credit_row(name))

      socket
      |> assign_form(Media.change_media(socket.assigns.media, params))
      |> assign(
        provenance_hints:
          ProvenanceHints.for_list(
            socket.assigns.provenance_hints,
            "media_narrators",
            proposal.source
          )
      )
      |> refresh_chips()
    end
  end

  # What a chip stages, which is a lookup and never a write — see the book
  # form for why a chip answers differently from the picker beside it. The
  # middle answer credits a person the library already holds with an identity
  # they were missing, rather than making a second record of them.
  defp credit_row(name) do
    case People.find_credit(:narrator, name) do
      {:credit, id} -> %{"narrator_id" => to_string(id)}
      {:person, id} -> %{"narrator" => %{"name" => name, "person_id" => to_string(id)}}
      :none -> %{"narrator" => %{"name" => name}}
    end
  end

  defp refresh_chips(socket) do
    %{evidence: evidence, form: form} = socket.assigns

    chips =
      if evidence && Evidence.proposing?(evidence) do
        %{
          # The record's own title, offered against the *override* — which is
          # what a recording is called when it differs from the book, and an
          # edition's title is the one place that difference is written down.
          title:
            evidence
            |> Evidence.proposals(:title)
            |> mark_chosen(%{"title" => Changeset.get_field(form.source, :title)}),
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
          # From the params, not the changeset: `image_type`,
          # `image_import_url` and the cleared `image_path` are form state
          # rather than schema fields, so `get_field/2` answers nil for all
          # three and no cover proposal ever came back chosen. The chip went
          # grey the moment it was clicked, which is the one moment it should
          # not have.
          image:
            evidence
            |> Evidence.proposals(:image)
            |> mark_chosen(Map.take(form.params, @image_params)),
          narrators:
            evidence
            |> Evidence.proposals(:narrators)
            |> mark_present(
              current_labels(
                form.source,
                :media_narrators,
                :narrator_id,
                &People.narrator_option/1,
                :narrator
              )
            )
        }
      else
        %{}
      end

    assign(socket, chips: chips, reverts: reverts(socket))
  end

  defp reverts(%{assigns: %{form: form, media: media}}),
    do: Revert.offers(form, media, [:title, :published, :publisher, :description, :image])

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

  # The file's own art, extracted at save the way an import extracts it. The
  # path is taken from the recording rather than from a param: what the form
  # accepted was "this recording's embedded cover", and the only honest
  # reading of that is the recording's own files.
  defp handle_embedded_image(socket, %{"image_type" => "embedded"} = media_params) do
    with [path | _rest] <- Media.Media.files(socket.assigns.media, Media.Scanner.extensions()),
         {:ok, web_path} <- Images.extract_embedded(path) do
      {:ok, Map.put(media_params, "image_path", web_path)}
    else
      _no_art -> {:error, :failed_import}
    end
  end

  defp handle_embedded_image(_socket, media_params), do: {:ok, media_params}

  defp handle_image_import(url, media_params) do
    case handle_image_import(url) do
      {:ok, :no_image_url} -> {:ok, media_params}
      {:ok, path} -> {:ok, Map.put(media_params, "image_path", path)}
      {:error, _reason} -> {:error, :failed_import}
    end
  end

  defp save_media(socket, :edit, media_params) do
    opts = [provenance: ProvenanceHints.sources(socket.assigns.provenance_hints)]
    media_params = NewPerson.import_photos(media_params, "media_narrators")

    case Media.update_media(socket.assigns.media, media_params, opts) do
      {:ok, media} ->
        # a title override or a changed date moves the folder
        {:ok, _job} = Media.organize_async(media)

        {:noreply,
         socket
         |> put_flash(:info, "Updated audiobook for #{media.book.title}")
         |> push_navigate(
           to: ReturnTo.path(~p"/admin/audiobooks", socket.assigns.list_params, media.id)
         )}

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
      media_narrator_count: Reordering.row_count(changeset, :media_narrators)
    )
  end

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

  # The drop-down's escape hatch, and the reason a blank id inside the set row
  # does not mean "no set": leaving the set is the ✕, which is an event.
  defp new_set_option, do: %{id: "", label: "New set"}

  defp preview_date_format(form) do
    format_published(%{
      published_format: Ecto.Changeset.get_field(form.source, :published_format),
      published: Ecto.Changeset.get_field(form.source, :published)
    })
  end
end
