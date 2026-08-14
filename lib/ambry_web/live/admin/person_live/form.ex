defmodule AmbryWeb.Admin.PersonLive.Form do
  @moduledoc """
  The person form, curated the import form's way: one name search fans out
  to every person-capable provider, results are tickable records of humans,
  and ticked records offer the photos and bios below. This replaced both the
  per-provider import modal and the separate image-picker modal — one
  mechanism for "ask the databases about this person".

  ## Credits are two questions, not two lists

  `Author` and `Narrator` are not roles — they are **credit names**, the name
  a book or a recording is credited to. The form used to say so out loud: two
  list clusters ("Writing as", "Narrating as") the operator had to populate,
  which meant that having just typed "Stephen King" into the name box you
  were then asked to add an author, and the answer was "Stephen King" again.
  A schema detail, charged to every ordinary person.

  So the common case is two checkboxes and no boxes to fill: **writes books**,
  **narrates audiobooks**, each credited under the person's own name, which
  is *stated* rather than typed. "Both" stops being a special case — it is
  two ticks. Ticking creates the credit; unticking removes it, and
  `People.update_person/3` deletes the freed record or refuses the save when
  a book still credits it (`delete_orphaned_authors/2`), so the checkbox
  cannot orphan anything.

  The rare cases are escape hatches wearing the import form's own vocabulary
  (§9), because an operator meets them there first: **"Writes under a pen
  name"** reveals the names as an editable list, and only in that state does
  linking an existing author appear — the composite case (James S.A. Corey),
  where one credit name is backed by several humans. A person whose data
  already diverges opens revealed, so nothing is hidden behind a control
  nobody clicked.

  Narrators get the same shape without the linking hatch: a `Narrator`
  belongs to exactly one `Person`, so there is no shared-narrator case to
  offer. The asymmetry is the model's, and the form states it rather than
  faking symmetry.

  ## The name follows

  While a credit is the person's own name, it *is* their name: renaming the
  person renames it. It used to not, so renaming Stephen King left an author
  called Stephen King behind, credited on every one of his books. The sync is
  guarded twice — the credit must currently match the old name, and an author
  backed by more than one person is never touched, because one human renaming
  themselves must not rename a pen name they share.
  """
  use AmbryWeb, :admin_live_view

  import AmbryWeb.Admin.Curation
  import AmbryWeb.Admin.UploadHelpers

  alias Ambry.Metadata.Search, as: MetadataSearch
  alias Ambry.People
  alias Ambry.People.Author
  alias Ambry.People.Person
  alias AmbryWeb.Admin.Evidence
  alias AmbryWeb.Admin.ProvenanceHints
  alias Ecto.Changeset

  @scalar_kinds %{"name" => :name, "description" => :description, "image" => :image}

  @impl Phoenix.LiveView
  def mount(params, _session, socket) do
    {:ok,
     socket
     |> allow_image_upload(:image)
     |> assign(
       retrying: nil,
       chips: %{},
       provenance_hints: %{},
       authors: People.authors_for_select(),
       # The escape hatches, once clicked. Data that already diverges reveals
       # itself without them — see `revealed?/2`.
       reveal: MapSet.new()
     )
     |> apply_action(socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    person = People.get_person!(id)
    changeset = People.change_person(person, %{"image_type" => "upload"})

    socket
    |> assign(reveal: seed_reveal(person))
    |> assign_form(changeset)
    |> assign(
      page_title: person.name,
      person: person,
      evidence: Evidence.new(%{"name" => person.name}, known: Evidence.known_from(person))
    )
  end

  defp apply_action(socket, :new, _params) do
    person = %Person{}
    changeset = People.change_person(person, %{"image_type" => "upload"})

    socket
    |> assign_form(changeset)
    |> assign(
      page_title: "New Author or Narrator",
      person: person,
      evidence: Evidence.new(%{})
    )
  end

  @impl Phoenix.LiveView
  def handle_params(_params, _url, socket), do: {:noreply, socket}

  @impl Phoenix.LiveView
  def handle_event("validate", %{"person" => person_params}, socket) do
    socket = assign(socket, reveal: reveal_after(socket.assigns.reveal, person_params))

    person_params =
      person_params
      |> maybe_link_author()
      |> apply_credits(socket.assigns.person, socket.assigns.reveal)

    socket =
      if person_params["image_type"] == "upload" do
        socket
      else
        cancel_all_uploads(socket, :image)
      end

    changeset =
      socket.assigns.person
      |> People.change_person(person_params)
      |> Map.put(:action, :validate)

    {:noreply,
     socket
     |> assign_form(changeset)
     |> assign(
       provenance_hints: ProvenanceHints.prune(socket.assigns.provenance_hints, person_params)
     )
     |> refresh_chips()}
  end

  def handle_event("submit", %{"person" => person_params}, socket) do
    person_params =
      person_params
      |> maybe_link_author()
      |> apply_credits(socket.assigns.person, socket.assigns.reveal)

    socket =
      assign(socket,
        provenance_hints: ProvenanceHints.prune(socket.assigns.provenance_hints, person_params)
      )

    with {:ok, _person} <-
           socket.assigns.person
           |> People.change_person(person_params)
           |> Changeset.apply_action(:insert),
         {:ok, person_params} <- handle_image_upload(socket, person_params, :image),
         {:ok, person_params} <-
           handle_image_import(person_params["image_import_url"], person_params) do
      save_person(socket, socket.assigns.live_action, person_params)
    else
      {:error, %Changeset{} = changeset} -> {:noreply, assign_form(socket, changeset)}
      {:error, :failed_upload} -> {:noreply, put_flash(socket, :error, "Failed to upload image")}
      {:error, :failed_import} -> {:noreply, put_flash(socket, :error, "Failed to import image")}
    end
  end

  def handle_event("cancel-upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :image, ref)}
  end

  # Every way in needs a way out: the reveal used to be the permanent shape
  # of the form, so there was nothing to go back to.
  # Both re-derive through `assign_form/2`, because the reveal set feeds the
  # checkbox: revealing without it left the box rendering unchecked, and the
  # next change event read that back as "untick" and swept the credit away.
  def handle_event("reveal-credit", %{"kind" => kind}, socket) do
    socket = assign(socket, reveal: MapSet.put(socket.assigns.reveal, atom_kind(kind)))
    {:noreply, assign_form(socket, socket.assigns.form.source)}
  end

  def handle_event("hide-credit", %{"kind" => kind}, socket) do
    socket = assign(socket, reveal: MapSet.delete(socket.assigns.reveal, atom_kind(kind)))
    {:noreply, assign_form(socket, socket.assigns.form.source)}
  end

  # ── the evidence panel ─────────────────────────────────────────────────

  def handle_event("research", %{"name" => name}, socket) do
    case String.trim(name || "") do
      "" ->
        {:noreply, socket}

      name ->
        {:noreply,
         socket
         |> assign(evidence: Evidence.begin(socket.assigns.evidence, %{"name" => name}))
         |> start_async(:evidence_search, fn -> MetadataSearch.people(name) end)}
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
      changeset = People.change_person(socket.assigns.person, new_params)

      {:noreply,
       socket
       |> assign_form(changeset)
       |> assign(provenance_hints: Map.merge(socket.assigns.provenance_hints, hints))
       |> refresh_chips()}
    else
      _missing -> {:noreply, socket}
    end
  end

  defp atom_kind("author"), do: :author
  defp atom_kind("narrator"), do: :narrator

  @impl Phoenix.LiveView
  def handle_async(:evidence_search, {:ok, result}, socket) do
    {:noreply,
     socket
     |> assign(evidence: Evidence.absorb_people(socket.assigns.evidence, result), retrying: nil)
     |> refresh_chips()}
  end

  def handle_async(:evidence_search, {:exit, _reason}, socket) do
    {:noreply,
     socket
     |> assign(evidence: %{socket.assigns.evidence | running?: false}, retrying: nil)
     |> put_flash(:error, "Searching the providers failed. Try again.")}
  end

  defp refresh_chips(socket) do
    %{evidence: evidence, form: form} = socket.assigns

    chips =
      if evidence && Evidence.any_used?(evidence) do
        %{
          name:
            evidence
            |> Evidence.proposals(:name)
            |> mark_chosen(%{"name" => Changeset.get_field(form.source, :name)}),
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
            })
        }
      else
        %{}
      end

    assign(socket, chips: chips)
  end

  defp cancel_all_uploads(socket, upload) do
    Enum.reduce(socket.assigns.uploads[upload].entries, socket, fn entry, socket ->
      cancel_upload(socket, upload, entry.ref)
    end)
  end

  defp handle_image_upload(socket, person_params, name) do
    case consume_uploaded_image(socket, name) do
      {:ok, :no_file} -> {:ok, person_params}
      {:ok, path} -> {:ok, Map.put(person_params, "image_path", path)}
      {:error, _reason} -> {:error, :failed_upload}
    end
  end

  defp handle_image_import(url, person_params) do
    case handle_image_import(url) do
      {:ok, :no_image_url} -> {:ok, person_params}
      {:ok, path} -> {:ok, Map.put(person_params, "image_path", path)}
      {:error, _reason} -> {:error, :failed_import}
    end
  end

  defp save_person(socket, :edit, person_params) do
    opts = [provenance: ProvenanceHints.sources(socket.assigns.provenance_hints)]

    case People.update_person(socket.assigns.person, person_params, opts) do
      {:ok, person} ->
        {:noreply,
         socket
         |> put_flash(:info, "Updated #{person.name}")
         |> push_navigate(to: ~p"/admin/people")}

      {:error, %Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save_person(socket, :new, person_params) do
    opts = [provenance: ProvenanceHints.sources(socket.assigns.provenance_hints)]

    case People.create_person(person_params, opts) do
      {:ok, person} ->
        {:noreply,
         socket
         |> put_flash(:info, "Created #{person.name}")
         |> push_navigate(to: ~p"/admin/people")}

      {:error, %Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp assign_form(socket, %Changeset{} = changeset) do
    name = Changeset.get_field(changeset, :name)
    author_people = Changeset.get_field(changeset, :author_people) || []
    narrators = Changeset.get_field(changeset, :narrators) || []

    reveal = socket.assigns[:reveal] || MapSet.new()

    socket
    |> assign(:form, to_form(changeset))
    # Revealed counts as on even with nothing in the list yet: taking the
    # pen-name hatch is how a person who is not yet an author gets to the
    # link control, and the composite case (linking James S.A. Corey to his
    # second human) starts exactly there. Auto-creating an own-name author
    # for them would mean deleting it again a click later.
    |> assign(:writes, author_people != [] or :author in reveal)
    |> assign(:narrates, narrators != [] or :narrator in reveal)
    # Data that already disagrees with "credited under their own name" opens
    # revealed: a pen name hidden behind a control nobody clicked is a pen
    # name the operator can't see, and this form is where they go to find it.
    |> assign(:author_diverges, Enum.any?(author_people, &author_diverges?(&1, name)))
    |> assign(:narrator_diverges, Enum.any?(narrators, &(&1.name != name)))
  end

  # A pen name in either of the two senses: a name that isn't theirs, or a
  # name that isn't only theirs.
  defp author_diverges?(%{author: %Author{} = author}, name),
    do: author.name != name or shared?(author)

  defp author_diverges?(_unloaded, _name), do: false

  defp shared?(%Author{people: people}) when is_list(people), do: length(people) > 1
  defp shared?(_author), do: false

  @doc """
  Whether a credit's names are showing as an editable list.

  Either because the operator asked, or because the data says something the
  checkbox alone cannot.
  """
  def revealed?(assigns, kind), do: kind in assigns.reveal

  # Seeded once, from the record as it was opened — never re-derived from the
  # changeset. Deriving it per render meant the hatch was computed from the
  # very field the operator was typing in: renaming the pen name "Bar" to
  # "Alastair Reynolds" made it stop differing from his name, so the card
  # collapsed mid-edit, stopped rendering the rows, and dropped the rename on
  # the floor. A disclosure may not close itself because of what was just
  # typed into it.
  defp seed_reveal(%Person{} = person) do
    Enum.reduce(
      [
        {:author, Enum.any?(loaded(person.author_people), &author_diverges?(&1, person.name))},
        {:narrator, Enum.any?(loaded(person.narrators), &(&1.name != person.name))}
      ],
      MapSet.new(),
      fn
        {kind, true}, reveal -> MapSet.put(reveal, kind)
        {_kind, false}, reveal -> reveal
      end
    )
  end

  # Unticking collapses the hatch with it — a revealed list under an
  # unchecked box describes credits that no longer exist.
  defp reveal_after(reveal, person_params) do
    reveal
    |> drop_if(:author, person_params["writes"] == "false")
    |> drop_if(:narrator, person_params["narrates"] == "false")
  end

  defp drop_if(reveal, kind, true), do: MapSet.delete(reveal, kind)
  defp drop_if(reveal, _kind, _false), do: reveal

  # The checkboxes, and the name that follows them, reconciled with the rows
  # they stand for.
  #
  # It runs on every keystroke, so it has to be idempotent, and the ordinary
  # case has to be "change nothing". Absent params mean "leave the
  # association alone" — Ecto's own rule — so an unrevealed credit says
  # nothing about rows it doesn't render, and only a real transition writes.
  defp apply_credits(person_params, person, reveal) do
    person_params
    |> reconcile_authors(person, :author in reveal)
    |> reconcile_narrators(person, :narrator in reveal)
  end

  defp reconcile_authors(params, person, revealed?) do
    name = params["name"] || ""
    rows = loaded(person.author_people)

    cond do
      # Unticked: the whole collection goes. `on_replace: :delete` unlinks
      # the rows, and `People.update_person/3` then deletes what nothing
      # credits — or refuses the save and names the book that still does.
      params["writes"] == "false" ->
        Map.put(params, "author_people", %{})

      # Revealed: the operator is naming these themselves, in inputs that
      # are already in the params. Nothing to reconcile and nothing to sync.
      params["author_people"] != nil ->
        params

      # The tick itself.
      # Ticked from the plain state: credited under their own name. Ticked
      # from the revealed one: the operator is about to say what the name
      # is, so the list starts empty.
      rows == [] and params["writes"] == "true" and not revealed? ->
        put_row(params, "author_people", %{"author" => %{"name" => name}})

      name != person.name ->
        Map.put(params, "author_people", author_sync(rows, person, name))

      true ->
        params
    end
  end

  defp reconcile_narrators(params, person, revealed?) do
    name = params["name"] || ""
    rows = loaded(person.narrators)

    cond do
      params["narrates"] == "false" ->
        Map.put(params, "narrators", %{})

      params["narrators"] != nil ->
        params

      rows == [] and params["narrates"] == "true" and not revealed? ->
        put_row(params, "narrators", %{"name" => name})

      name != person.name ->
        Map.put(params, "narrators", narrator_sync(rows, person, name))

      true ->
        params
    end
  end

  defp put_row(params, key, row), do: Map.put(params, key, %{"0" => row})

  # A rename, carried to the credits that are this person's own name.
  #
  # The whole collection is re-emitted, because emitting some rows and not
  # others would delete the rest — `cast_assoc` reads params as the complete
  # list. Rows that don't sync are emitted as a bare id, which updates
  # nothing.
  # The author's own id rides along: `AuthorPerson` casts `:author` with
  # `on_replace: :raise`, so params without it are read as "replace this
  # author with a new one" and blow up rather than renaming.
  defp author_sync(rows, person, new_name) do
    index_rows(rows, fn author_person ->
      if syncs_name?(author_person.author, person),
        do: %{"author" => %{"id" => to_string(author_person.author.id), "name" => new_name}},
        else: %{}
    end)
  end

  defp narrator_sync(rows, person, new_name) do
    index_rows(rows, fn narrator ->
      if narrator.name == person.name, do: %{"name" => new_name}, else: %{}
    end)
  end

  defp index_rows(rows, changes) do
    rows
    |> Enum.with_index()
    |> Map.new(fn {row, index} ->
      {to_string(index), Map.put(changes.(row), "id", to_string(row.id))}
    end)
  end

  # Guarded twice: the credit has to *be* their current name, and a shared
  # pen name is never touched — one of James S.A. Corey's two humans
  # renaming themselves must not rename James S.A. Corey.
  defp syncs_name?(%Author{} = author, person),
    do: author.name == person.name and not shared?(author)

  defp syncs_name?(_unloaded, _person), do: false

  defp loaded(rows) when is_list(rows), do: rows
  defp loaded(_not_loaded), do: []

  # Selecting an author in the "link an existing author" autocomplete stages an
  # `author_people` row linking that author (unless it's already present).
  defp maybe_link_author(%{"link_author_id" => id} = person_params) when id not in [nil, ""] do
    author_people = person_params["author_people"] || %{}

    linked_ids =
      author_people
      |> Map.values()
      |> Enum.flat_map(&[&1["author_id"], get_in(&1, ["author", "id"])])
      |> Enum.reject(&is_nil/1)
      |> Enum.map(&to_string/1)

    person_params = Map.put(person_params, "link_author_id", "")

    if to_string(id) in linked_ids do
      person_params
    else
      next_index =
        author_people
        |> Map.keys()
        |> Enum.map(&String.to_integer/1)
        |> Enum.max(fn -> -1 end)
        |> Kernel.+(1)
        |> to_string()

      sort = person_params["author_people_sort"] || []

      person_params
      |> Map.put("author_people", Map.put(author_people, next_index, %{"author_id" => id}))
      |> Map.put("author_people_sort", sort ++ [next_index])
    end
  end

  defp maybe_link_author(person_params), do: person_params

  defp linked_author_row?(author_person_form) do
    is_nil(author_person_form.data.id) and
      author_person_form[:author_id].value not in [nil, ""]
  end

  defp linked_author_name(authors, value) do
    Enum.find_value(authors, fn option ->
      to_string(option.id) == to_string(value) && option.label
    end)
  end

  defp shared_with(author_person_form, person) do
    case author_person_form.data.author do
      %Author{people: people} when is_list(people) ->
        people
        |> Enum.reject(&(&1.id == person.id))
        |> Enum.map(& &1.name)

      _author ->
        []
    end
  end
end
