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
  alias Ambry.People.Person
  alias AmbryWeb.Admin.Evidence
  alias AmbryWeb.Admin.ProvenanceHints
  alias AmbryWeb.Admin.Reordering
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
       provenance_hints: %{},
       authors: People.authors_for_select(),
       series: Books.series_for_select(),
       universes: Books.universes_for_select()
     )
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
    |> assign(
      evidence:
        Evidence.new(seed_fields(book, socket.assigns.authors), known: Evidence.known_from(book))
    )
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
  defp seed_fields(book, author_options) do
    labels = Map.new(author_options, &{&1.id, &1.label})

    author =
      case book.book_authors do
        [%{author_id: author_id} | _rest] -> labels[author_id]
        _empty -> nil
      end

    %{"title" => book.title, "author" => author}
  end

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

  def handle_event("move", params, socket) do
    changeset = socket.assigns.form.source
    book_params = Reordering.move(changeset, socket.assigns.form.params, params)

    {:noreply, assign_form(socket, Books.change_book(socket.assigns.book, book_params))}
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
    author_id = resolve_author(proposal.params["name"], proposal.source)

    socket
    |> append_row(:book_authors, %{"author_id" => to_string(author_id)}, ~w(author_id))
    |> assign(
      authors: People.authors_for_select(),
      provenance_hints:
        ProvenanceHints.for_list(socket.assigns.provenance_hints, "book_authors", proposal.source)
    )
    |> refresh_chips()
  end

  defp accept_entity(socket, :series, proposal) do
    series_id = resolve_series(proposal.params["name"])

    row =
      %{"series_id" => to_string(series_id)}
      |> Map.merge(
        (proposal.params["number"] && %{"book_number" => proposal.params["number"]}) || %{}
      )

    socket
    |> append_row(:series_books, row, ~w(series_id book_number))
    |> assign(
      series: Books.series_for_select(),
      provenance_hints:
        ProvenanceHints.for_list(socket.assigns.provenance_hints, "series_books", proposal.source)
    )
    |> refresh_chips()
  end

  # The author identity a proposed credit names: an existing author of that
  # name, the author identity added to an existing person of that name, or a
  # brand-new person — created with provider provenance on their name.
  defp resolve_author(name, source) do
    case Ambry.Search.find_first(name, Person) do
      nil ->
        {:ok, %{author_people: [%{author: author}]}} =
          People.create_person(
            %{name: name, author_people: [%{author: %{name: name}}]},
            provenance: %{"name" => source}
          )

        author.id

      %Person{authors: []} = person ->
        {:ok, %{author_people: [%{author: author}]}} =
          People.update_person(person, %{author_people: [%{author: %{name: person.name}}]})

        author.id

      %Person{authors: authors} ->
        credited =
          Enum.find(authors, &(String.downcase(&1.name) == String.downcase(name))) ||
            List.first(authors)

        credited.id
    end
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

  # Appends one row to a has_many by rebuilding the full row list from the
  # changeset — existing rows keep their ids (and their place), the new one
  # goes last. The sort/drop params are dropped because they describe the
  # params they arrived with, not the rebuilt list.
  defp append_row(socket, assoc, new_row, keep_fields) do
    changeset = socket.assigns.form.source

    rows =
      changeset
      |> Changeset.get_field(assoc)
      |> Enum.map(fn row ->
        base = if row.id, do: %{"id" => to_string(row.id)}, else: %{}

        Enum.reduce(keep_fields, base, fn field, acc ->
          case Map.get(row, String.to_existing_atom(field)) do
            nil -> acc
            value -> Map.put(acc, field, to_string(value))
          end
        end)
      end)

    params =
      socket.assigns.form.params
      |> Map.drop(["#{assoc}_sort", "#{assoc}_drop"])
      |> Map.put(to_string(assoc), rows ++ [new_row])

    assign_form(socket, Books.change_book(socket.assigns.book, params))
  end

  # ── what the ticked evidence proposes, marked against the form ─────────

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
              current_labels(form.source, :book_authors, :author_id, socket.assigns.authors)
            ),
          series:
            evidence
            |> Evidence.proposals(:series)
            |> mark_present(current_series_names(form.source, socket.assigns.series))
        }
      else
        %{}
      end

    assign(socket, chips: chips)
  end

  defp current_labels(changeset, assoc, key, options) do
    labels = Map.new(options, &{&1.id, &1.label})

    changeset
    |> Changeset.get_field(assoc)
    |> Enum.map(&labels[Map.get(&1, key)])
    |> Enum.reject(&is_nil/1)
  end

  defp current_series_names(changeset, options) do
    names = Map.new(options, fn {name, id} -> {id, name} end)

    changeset
    |> Changeset.get_field(:series_books)
    |> Enum.map(&names[&1.series_id])
    |> Enum.reject(&is_nil/1)
  end

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
         |> push_navigate(to: ~p"/admin/books")}

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
         |> push_navigate(to: ~p"/admin/books")}

      {:error, %Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp assign_form(socket, %Changeset{} = changeset) do
    assign(socket,
      form: to_form(changeset),
      # the move buttons need to know where the ends of each list are, and
      # the empty states whether there is a list at all
      book_author_count: length(Changeset.get_assoc(changeset, :book_authors)),
      series_book_count: length(Changeset.get_assoc(changeset, :series_books)),
      book_universe_count: length(Changeset.get_assoc(changeset, :book_universes))
    )
  end

  defp preview_date_format(form) do
    format_published(%{
      published_format: Ecto.Changeset.get_field(form.source, :published_format),
      published: Ecto.Changeset.get_field(form.source, :published)
    })
  end
end
