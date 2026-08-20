defmodule AmbryWeb.Admin.BookLive.Form do
  @moduledoc """
  The book form, curated the import form's way: one search fans out to every
  work-level provider, results are tickable evidence, and ticked records
  grow "Proposed" chips under the fields they can fill. Accepting a chip
  takes the value and records the source (`Ambry.Provenance`) on save.

  This replaced the per-provider import modal — one provider and one record
  per trip, and checkboxes that could say *whether* to take a field but
  never which source it came from.
  """
  use AmbryWeb, :admin_live_view

  import AmbryWeb.Admin.Curation

  alias Ambry.Books
  alias Ambry.Books.Book
  alias Ambry.Books.Series
  alias Ambry.Inbox
  alias Ambry.Media
  alias Ambry.Metadata.Provider
  alias Ambry.Metadata.Registry
  alias Ambry.Metadata.Search, as: MetadataSearch
  alias Ambry.People
  alias AmbryWeb.Admin.Evidence
  alias AmbryWeb.Admin.ProvenanceHints
  alias AmbryWeb.Admin.Reordering
  alias AmbryWeb.Admin.ReturnTo
  alias AmbryWeb.Admin.Revert
  alias Ecto.Changeset

  # the scalar fields evidence can propose, by their wire names
  @scalar_kinds %{"title" => :title, "published" => :published}
  @entity_kinds %{"authors" => :authors, "series" => :series}

  @impl Phoenix.LiveView
  def mount(params, _session, socket) do
    {:ok,
     socket
     |> assign(
       retrying: nil,
       chips: %{},
       reverts: %{},
       provenance_hints: %{}
     )
     # The list the operator came from, kept so every way out of this form
     # goes back to it. See `AmbryWeb.Admin.ReturnTo`.
     |> assign(list_params: ReturnTo.list_params(params))
     |> apply_action(socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    book = Books.get_book!(id)
    changeset = Books.change_book(book)

    socket
    |> assign(
      page_title: book.title,
      book: book
    )
    |> assign_form(changeset)
    |> assign(evidence: Evidence.new(seed_fields(book), known: Evidence.known_from(book)))
  end

  defp apply_action(socket, :new, _params) do
    book = %Book{book_authors: [], series_books: []}
    changeset = Books.change_book(book)

    socket
    |> assign(
      page_title: "New Book",
      book: book
    )
    |> assign_form(changeset)
    |> assign(evidence: Evidence.new(%{}))
  end

  # The search the record itself suggests: its title, and its first author.
  # Read off the loaded credit rather than looked up in a list of every author
  # in the library, which is what it used to need.
  defp seed_fields(book) do
    %{"title" => book.title, "author" => first_author(book)}
  end

  defp first_author(%{book_authors: [%{author: %{name: name}} | _rest]}), do: name
  defp first_author(_book), do: nil

  @impl Phoenix.LiveView
  def handle_params(_params, _url, socket), do: {:noreply, socket}

  @impl Phoenix.LiveView
  def handle_event("validate", %{"book" => book_params}, socket) do
    changeset =
      socket.assigns.book
      |> Books.change_book(book_params)
      |> Map.put(:action, :validate)

    {:noreply,
     socket
     |> assign_form(changeset)
     |> assign(
       provenance_hints: ProvenanceHints.prune(socket.assigns.provenance_hints, book_params)
     )
     |> refresh_chips()}
  end

  def handle_event("submit", %{"book" => book_params}, socket) do
    socket =
      assign(socket,
        provenance_hints: ProvenanceHints.prune(socket.assigns.provenance_hints, book_params)
      )

    socket.assigns.book
    |> Books.change_book(book_params)
    |> Changeset.apply_action(:insert)
    |> case do
      {:ok, _book} -> save_book(socket, socket.assigns.live_action, book_params)
      {:error, %Changeset{} = changeset} -> {:noreply, assign_form(socket, changeset)}
    end
  end

  # ── the evidence panel ─────────────────────────────────────────────────

  def handle_event("research", params, socket) do
    fields = Map.take(params, ["title", "author"])
    query = Provider.Query.from_fields(fields)

    if Provider.Query.blank?(query) do
      {:noreply, socket}
    else
      hints = Inbox.form_hints(%{title: params["title"], author: params["author"]})

      {:noreply,
       socket
       |> assign(evidence: Evidence.begin(socket.assigns.evidence, fields))
       |> start_async(:evidence_search, fn ->
         {found, outcomes} = MetadataSearch.books(query, level: :work)

         records =
           Enum.flat_map(found, fn {entry, books} -> Inbox.score_records(books, entry, hints) end)

         {records, outcomes}
       end)}
    end
  end

  def handle_event("retry-provider", %{"provider" => provider_id}, socket) do
    query = Provider.Query.from_fields(socket.assigns.evidence.fields)

    with false <- Provider.Query.blank?(query),
         {:ok, entry} <- Registry.fetch(provider_id) do
      hints =
        socket.assigns.evidence.fields
        |> Map.new(fn {k, v} -> {String.to_existing_atom(k), v} end)
        |> Inbox.form_hints()

      {:noreply,
       socket
       |> assign(retrying: provider_id)
       |> start_async(:evidence_search, fn ->
         {books, outcome} = MetadataSearch.books_one(entry, query)
         {Inbox.score_records(books, entry, hints), List.wrap(outcome)}
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
      {:noreply, accept_params(socket, proposal.params, proposal.source)}
    else
      _missing -> {:noreply, socket}
    end
  end

  # The way back out of a chip. Restores the field from the saved record and
  # drops the pending provenance with it: nothing was accepted after all, so
  # nothing should be recorded as accepted.
  def handle_event("revert-field", %{"field" => field}, socket) do
    case Map.fetch(@scalar_kinds, field) do
      {:ok, kind} ->
        params = Map.merge(socket.assigns.form.params, Revert.params(socket.assigns.book, kind))
        hints = Map.delete(socket.assigns.provenance_hints, field)

        {:noreply,
         socket
         |> assign_form(Books.change_book(socket.assigns.book, params))
         |> assign(provenance_hints: hints)
         |> refresh_chips()}

      :error ->
        {:noreply, socket}
    end
  end

  def handle_event("accept-entity", %{"field" => field, "key" => key}, socket) do
    with {:ok, kind} <- Map.fetch(@entity_kinds, field),
         %{} = proposal <- Evidence.find_proposal(socket.assigns.evidence, kind, key) do
      {:noreply, accept_entity(socket, kind, proposal)}
    else
      _missing -> {:noreply, socket}
    end
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

  # ── accepting proposals ────────────────────────────────────────────────

  # A scalar acceptance is a param merge plus a provenance hint per param —
  # the hint dies if the operator edits the value afterwards, and saving
  # records the source for whatever hints survive.
  defp accept_params(socket, params, source) do
    hints = ProvenanceHints.from_import(params, source)
    new_params = Map.merge(socket.assigns.form.params, params)
    changeset = Books.change_book(socket.assigns.book, new_params)

    socket
    |> assign_form(changeset)
    |> assign(provenance_hints: Map.merge(socket.assigns.provenance_hints, hints))
    |> refresh_chips()
  end

  defp accept_entity(socket, :authors, proposal) do
    author = People.find_or_create_author(proposal.params["name"], source: proposal.source)
    author_id = author.id

    if already_credited?(socket, :book_authors, :author_id, author_id) do
      socket
    else
      socket
      |> assign_rows(:book_authors, %{"author_id" => to_string(author_id)}, ~w(author_id))
      |> assign(
        provenance_hints:
          ProvenanceHints.for_list(
            socket.assigns.provenance_hints,
            "book_authors",
            proposal.source
          )
      )
      |> refresh_chips()
    end
  end

  defp accept_entity(socket, :series, proposal) do
    series_id = resolve_series(proposal.params["name"])

    row =
      %{"series_id" => to_string(series_id)}
      |> Map.merge(
        (proposal.params["number"] && %{"book_number" => proposal.params["number"]}) || %{}
      )

    if already_credited?(socket, :series_books, :series_id, series_id) do
      socket
    else
      socket
      |> assign_rows(:series_books, row, ~w(series_id book_number))
      |> assign(
        provenance_hints:
          ProvenanceHints.for_list(
            socket.assigns.provenance_hints,
            "series_books",
            proposal.source
          )
      )
      |> refresh_chips()
    end
  end

  # Asked of the *resolved* record rather than of the chip: a chosen chip no
  # longer offers a click (`proposal_chip/1`), so reaching here means either a
  # stale page or two chips whose different names resolve to one author —
  # "J.R.R. Tolkien" and "John Ronald Reuel Tolkien" naming the same row. The
  # rendering rule is what the operator sees; this is what makes it true.
  #
  # `get_field/2` and not `get_assoc/2`: a row removed with the ✕ is still in
  # the association, marked for replacement, and counting it as credited made
  # the chip refuse to put back the author it had just let go of — the same
  # trap `Reordering.row_count/2` exists for. This is the applied list, which
  # is the list on screen.
  # `Curation.append_row/4` answers in params; this is the form putting them on.
  defp assign_rows(socket, assoc, new_row, keep_fields) do
    params = append_row(socket.assigns.form, assoc, new_row, keep_fields)
    assign_form(socket, Books.change_book(socket.assigns.book, params))
  end

  defp already_credited?(socket, assoc, key, id) do
    socket.assigns.form.source
    |> Changeset.get_field(assoc)
    |> Enum.any?(&(Map.get(&1, key) == id))
  end

  defp resolve_series(name) do
    case Ambry.Search.find_first(name, Series) do
      nil ->
        {:ok, series} = Books.create_series(%{name: name})
        series.id

      %Series{} = series ->
        series.id
    end
  end

  defp refresh_chips(socket) do
    %{evidence: evidence, form: form} = socket.assigns

    chips =
      if evidence && Evidence.any_used?(evidence) do
        %{
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
          authors:
            evidence
            |> Evidence.proposals(:authors)
            |> mark_present(
              current_labels(form.source, :book_authors, :author_id, &People.author_option/1)
            ),
          series:
            evidence
            |> Evidence.proposals(:series)
            |> mark_present(
              current_labels(form.source, :series_books, :series_id, &Books.series_option/1)
            )
        }
      else
        %{}
      end

    assign(socket, chips: chips, reverts: reverts(socket))
  end

  defp reverts(%{assigns: %{form: form, book: book}}),
    do: Revert.offers(form, book, [:title, :published])

  defp save_book(socket, :edit, book_params) do
    opts = [provenance: ProvenanceHints.sources(socket.assigns.provenance_hints)]

    case Books.update_book(socket.assigns.book, book_params, opts) do
      {:ok, book} ->
        # the title, primary author and primary series all appear in the path
        # of every managed recording of this book
        {:ok, _job} = Media.organize_book_async(book.id)

        {:noreply,
         socket
         |> put_flash(:info, "Updated #{book.title}")
         |> push_navigate(
           to: ReturnTo.path(~p"/admin/books", socket.assigns.list_params, book.id)
         )}

      {:error, %Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save_book(socket, :new, book_params) do
    opts = [provenance: ProvenanceHints.sources(socket.assigns.provenance_hints)]

    case Books.create_book(book_params, opts) do
      {:ok, book} ->
        {:noreply,
         socket
         |> put_flash(:info, "Created #{book.title}")
         |> push_navigate(
           to: ReturnTo.path(~p"/admin/books", socket.assigns.list_params, book.id)
         )}

      {:error, %Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp assign_form(socket, %Changeset{} = changeset) do
    assign(socket,
      form: to_form(changeset),
      # the move buttons need to know where the ends of each list are, and
      # the empty states whether there is a list at all
      book_author_count: Reordering.row_count(changeset, :book_authors),
      series_book_count: Reordering.row_count(changeset, :series_books),
      book_universe_count: Reordering.row_count(changeset, :book_universes)
    )
  end

  defp preview_date_format(form) do
    format_published(%{
      published_format: Ecto.Changeset.get_field(form.source, :published_format),
      published: Ecto.Changeset.get_field(form.source, :published)
    })
  end
end
