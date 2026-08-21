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
  import AmbryWeb.Admin.NewPerson, only: [new_person_card: 1, new_person_pill: 1]

  alias Ambry.Books
  alias Ambry.Books.Book
  alias Ambry.Inbox
  alias Ambry.Media
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

  # the scalar fields evidence can propose, by their wire names
  @scalar_kinds %{"title" => :title, "published" => :published}
  @entity_kinds %{"authors" => :authors, "series" => :series}
  @person_events NewPerson.events()

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
     |> NewPerson.mount()
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

  # ── the people this form is about to create ────────────────────────────
  #
  # The card owns its own evidence and its own state; the form owns the
  # assign it lives in and nothing else.
  def handle_event(event, params, socket) when event in @person_events,
    do: NewPerson.handle_event(event, params, socket)

  @impl Phoenix.LiveView
  def handle_async({:person_search, _key} = name, result, socket),
    do: NewPerson.handle_async(name, result, socket)

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

  # **A chip stages a name; it creates nothing.**
  #
  # It used to create: clicking a proposed author wrote a `Person` row on the
  # spot, so a book you never saved left a person behind, and the picker
  # beside it — which stages — disagreed with it about when a thing becomes
  # real. Both put the name in the row now, and the context resolves it inside
  # the transaction that saves the book (`Ambry.Ecto.EntityRef`). An edit form
  # does nothing until Save, without exception.
  defp accept_entity(socket, :authors, proposal) do
    name = proposal.params["name"]

    if credited?(socket, :book_authors, :author_id, &People.author_option/1, :author, name) do
      socket
    else
      socket
      |> assign_rows(:book_authors, credit_row(:author, name))
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
    name = proposal.params["name"]

    row =
      series_row(name)
      |> Map.merge(
        (proposal.params["number"] && %{"book_number" => proposal.params["number"]}) || %{}
      )

    if credited?(socket, :series_books, :series_id, &Books.series_option/1, :series, name) do
      socket
    else
      socket
      |> assign_rows(:series_books, row)
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

  # `Curation.append_row/4` answers in params; this is the form putting them on.
  defp assign_rows(socket, assoc, new_row) do
    params = append_row(socket.assigns.form, assoc, new_row)
    assign_form(socket, Books.change_book(socket.assigns.book, params))
  end

  # **What a chip stages, which is a lookup and never a write.** A chip is the
  # machine's proposal, not a choice between listed options: when the library
  # already has the human it names, that is who they are, and staging a new
  # one would make a second record of somebody the library knows. So the row
  # points where it can and brings what it must.
  #
  # The middle answer is the one worth having. A person the library holds who
  # has never been credited this way gains the identity — nested, so the join
  # is created while the person is merely linked — where a bare new author
  # would have been a second Ty Franck beside the first.
  defp credit_row(kind, name) do
    case People.find_credit(kind, name) do
      {:credit, id} -> %{"#{kind}_id" => to_string(id)}
      {:person, id} -> %{to_string(kind) => new_credit(kind, name, id)}
      :none -> %{to_string(kind) => %{"name" => name}}
    end
  end

  defp new_credit(:author, name, person_id),
    do: %{"name" => name, "author_people" => [%{"person_id" => to_string(person_id)}]}

  defp series_row(name) do
    case Books.find_series(name) do
      %{id: id} -> %{"series_id" => to_string(id)}
      nil -> %{"series" => %{"name" => name}}
    end
  end

  # Whether this list already credits that name, by pointing at it or by
  # holding it — a chip clicked once has staged a credit that is not saved
  # yet, and clicking it again must not stage it twice.
  defp credited?(socket, assoc, key, fetch, name_key, name) do
    credits_name?(socket.assigns.form.source, assoc, key, fetch, name_key, name)
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
              current_labels(
                form.source,
                :book_authors,
                :author_id,
                &People.author_option/1,
                :author
              )
            ),
          series:
            evidence
            |> Evidence.proposals(:series)
            |> mark_present(
              current_labels(
                form.source,
                :series_books,
                :series_id,
                &Books.series_option/1,
                :series
              )
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
    book_params = NewPerson.import_photos(book_params, "book_authors")

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
    book_params = NewPerson.import_photos(book_params, "book_authors")

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

  attr :book_author_form, :any, required: true
  attr :author_form, :any, required: true
  attr :new_people, :map, required: true

  # The humans behind one pen name, in the order the list holds them. Pulled
  # out of the template because the bracket renders the same cards as the
  # bare case and only the wrapper differs (design language §9).
  defp author_person_cards(assigns) do
    ~H"""
    <.inputs_for :let={author_person_form} field={@author_form[:author_people]}>
      <.sort_input field={@author_form[:author_people_sort]} index={author_person_form.index} />
      <.new_person_card
        row={author_person_form}
        key={"#{NewPerson.key(@book_author_form)}-#{author_person_form.index}"}
        state={
          NewPerson.state(
            @new_people,
            "#{NewPerson.key(@book_author_form)}-#{author_person_form.index}"
          )
        }
        credited={staged_name(@book_author_form, :author)}
        kind={:author}
        people_count={NewPerson.people_count(@book_author_form)}
        person_index={author_person_form.index}
        list_sort_name={@author_form[:author_people_sort].name}
        list_drop_name={@author_form[:author_people_drop].name}
        removable={author_person_form.index > 0}
      />
    </.inputs_for>
    """
  end

  defp preview_date_format(form) do
    format_published(%{
      published_format: Ecto.Changeset.get_field(form.source, :published_format),
      published: Ecto.Changeset.get_field(form.source, :published)
    })
  end
end
