defmodule AmbryWeb.Admin.PersonLive.Form do
  @moduledoc """
  The person form, curated the import form's way: one name search fans out to
  every person-capable provider, results are tickable records of humans, and
  ticked records offer the photos and bios below.

  **Credits are two questions, not two lists.** `Author` and `Narrator` are
  not roles: they are credit *names*, the name a book or recording is credited
  to. As two list clusters, having just typed a person's name you are asked to
  add an author and the answer is that name again.

  So the common case is two checkboxes: **writes books**, **narrates
  audiobooks**, each credited under the person's own name. Ticking creates the
  credit; unticking removes it, and `People.update_person/3` deletes the freed
  record or refuses the save when a book still credits it.

  The rare cases are escape hatches in the import form's vocabulary (§9):
  **"Writes under a pen name"** reveals the names as an editable list, and
  only there does linking an existing author appear, which is the composite
  case. A person whose data already diverges opens revealed.

  Narrators get the same shape without the linking hatch, because a `Narrator`
  belongs to exactly one `Person`. The asymmetry is the model's.

  While a credit is the person's own name it *is* their name, so renaming the
  person renames it, or an author under the previous name is left credited on
  every one of their books. Guarded twice: the credit must currently match the
  previous name, and an author backed by more than one person is never
  touched.
  """
  use AmbryWeb, :admin_live_view

  import AmbryWeb.Admin.Curation
  import AmbryWeb.Admin.UploadHelpers

  alias Ambry.Metadata.Search, as: MetadataSearch
  alias Ambry.People
  alias Ambry.People.Author
  alias Ambry.People.Person
  alias AmbryWeb.Admin.Deletion
  alias AmbryWeb.Admin.Evidence
  alias AmbryWeb.Admin.ProvenanceHints
  alias AmbryWeb.Admin.ReturnTo
  alias AmbryWeb.Admin.Revert
  alias Ecto.Changeset

  # The trio that carries a chosen cover through the form: two say where it
  # comes from and the third is the one being replaced.
  @image_params ~w(image_type image_import_url image_path)

  @scalar_kinds %{"name" => :name, "description" => :description, "image" => :image}

  @impl Phoenix.LiveView
  def mount(params, _session, socket) do
    {:ok,
     socket
     |> allow_image_upload(:image)
     |> assign(
       retrying: nil,
       chips: %{},
       reverts: %{},
       provenance_hints: %{},
       # The escape hatches, once clicked. Data that already diverges reveals
       # itself without them — see `revealed?/2`.
       reveal: MapSet.new()
     )
     # The list the operator came from, kept so every way out of this form
     # goes back to it. See `AmbryWeb.Admin.ReturnTo`.
     |> assign(list_params: ReturnTo.list_params(params))
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
  def handle_event("delete", _params, socket) do
    case Deletion.outcome(People.delete_person(socket.assigns.person), socket.assigns.person.name) do
      {:ok, message} ->
        {:noreply,
         socket
         |> put_flash(:info, message)
         |> push_navigate(to: ReturnTo.path(~p"/admin/people", socket.assigns.list_params))}

      {:error, message} ->
        {:noreply, put_flash(socket, :error, message)}
    end
  end

  def handle_event("validate", %{"person" => person_params}, socket) do
    socket = assign(socket, reveal: reveal_after(socket.assigns.reveal, person_params))

    person_params =
      person_params
      |> maybe_link_author()
      |> apply_credits(held(socket.assigns.form.source))

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
      |> apply_credits(held(socket.assigns.form.source))

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

  # Choosing is a named event, not a form field (the import form's rule). As
  # form data, every add and delete would arrive carrying a tick state
  # derived from the rows those very params are changing.
  def handle_event("toggle-credit", %{"kind" => kind}, socket) do
    kind = atom_kind(kind)
    name = Changeset.get_field(socket.assigns.form.source, :name) || ""

    {key, row} =
      case kind do
        :author -> {"author_people", %{"author" => %{"name" => name}}}
        :narrator -> {"narrators", %{"name" => name}}
      end

    on? = if kind == :author, do: socket.assigns.writes, else: socket.assigns.narrates

    params =
      Map.put(socket.assigns.form.params, key, if(on?, do: %{}, else: %{"0" => row}))

    changeset =
      socket.assigns.person
      |> People.change_person(params)
      |> Map.put(:action, :validate)

    {:noreply,
     socket
     |> assign(
       reveal:
         if(on?, do: MapSet.delete(socket.assigns.reveal, kind), else: socket.assigns.reveal)
     )
     |> assign_form(changeset)}
  end

  # Every way in needs a way out. Both re-derive through `assign_form/2`,
  # because the reveal set feeds the checkbox: without it the box renders
  # unchecked and the next change event reads that back as "untick".
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

  # The way back out of a chip: restores the field from the saved record and
  # drops the pending provenance with it.
  def handle_event("revert-field", %{"field" => field}, socket) do
    case Map.fetch(@scalar_kinds, field) do
      {:ok, kind} ->
        params = Map.merge(socket.assigns.form.params, Revert.params(socket.assigns.person, kind))
        hints = Map.drop(socket.assigns.provenance_hints, [field, "image_path"])

        {:noreply,
         socket
         |> assign_form(People.change_person(socket.assigns.person, params))
         |> assign(provenance_hints: hints)
         |> refresh_chips()}

      :error ->
        {:noreply, socket}
    end
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
          # From the params, not the changeset: `image_type`,
          # `image_import_url` and the cleared `image_path` are form state
          # rather than schema fields, so `get_field/2` answers nil for all
          # three and no photo proposal ever reads as chosen.
          image:
            evidence
            |> Evidence.proposals(:image)
            |> mark_chosen(Map.take(form.params, @image_params))
        }
      else
        %{}
      end

    assign(socket, chips: chips, reverts: reverts(socket))
  end

  defp reverts(%{assigns: %{form: form, person: person}}),
    do: Revert.offers(form, person, [:name, :description, :image])

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
         |> push_navigate(
           to: ReturnTo.path(~p"/admin/people", socket.assigns.list_params, person.id)
         )}

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
         |> push_navigate(
           to: ReturnTo.path(~p"/admin/people", socket.assigns.list_params, person.id)
         )}

      {:error, %Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp assign_form(socket, %Changeset{} = changeset) do
    name = Changeset.get_field(changeset, :name)
    author_people = Changeset.get_field(changeset, :author_people) || []
    narrators = Changeset.get_field(changeset, :narrators) || []

    socket
    |> assign(:form, to_form(changeset))
    # Revealed counts as on with nothing in the list yet: the pen-name hatch
    # is how a person who is not yet an author reaches the link control.

    # The rows and nothing else. Counting "revealed" too would leave the box
    # ticked after the last credit is deleted, until the save caught up.
    |> assign(:writes, author_people != [])
    |> assign(:narrates, narrators != [])
    # Data that already disagrees with "credited under their own name" opens
    # revealed: a pen name behind a control nobody clicked is one the operator
    # can't see.
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

  # Seeded once from the record as opened, never re-derived from the
  # changeset, which would compute the hatch from the very field being typed
  # in. A disclosure may not close itself because of what was typed into it.
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
  # they stand for. Runs on every keystroke, so it is idempotent. Absent
  # params mean "leave the association alone" (Ecto's rule), so an unrevealed
  # credit says nothing about rows it does not render.
  defp apply_credits(person_params, held) do
    person_params
    |> reconcile("author_people", held.author_people)
    |> reconcile("narrators", held.narrators)
  end

  # What the form is holding right now, which is what its params are meant
  # to describe.
  defp held(%Changeset{} = changeset) do
    %{
      author_people: Changeset.get_field(changeset, :author_people) || [],
      narrators: Changeset.get_field(changeset, :narrators) || []
    }
  end

  # The form renders every credit it holds, so absent params mean it holds
  # none. Emptying the list and unticking the box are the same instruction,
  # and both have to reach `cast_assoc` as an empty collection.
  defp reconcile(params, key, held) do
    if params[key] == nil and held == [], do: Map.put(params, key, %{}), else: params
  end

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

  # What a linked author is called. Asked of the context rather than found in
  # a preloaded list: naming a record is a lookup, not a reason to hold every
  # record of that kind in memory.
  defp linked_author_name(value) do
    case People.author_option(value) do
      %{label: label} -> label
      nil -> nil
    end
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
