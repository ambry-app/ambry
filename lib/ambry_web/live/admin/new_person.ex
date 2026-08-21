defmodule AmbryWeb.Admin.NewPerson do
  @moduledoc """
  The person an edit form is about to create, with the import form's card.

  A credit box that can name somebody the library has never heard of
  (`Ambry.Ecto.EntityRef`) makes a `Person` out of a name and nothing else —
  no face, no biography, no record of who said so. The same human created
  through the inbox arrives finished, because the import form asks about them
  on a card of their own. This is that card, on the edit forms.

  ## Nothing here writes params

  The card's fields *are* the person's fields — `book[book_authors][2]
  [author][author_people][0][person][description]` is a real input inside the
  book's own form element, cast by the same `cast_assoc` chain that creates
  the credit. A photo chip and a bio chip write into those inputs on the
  client and dispatch a change (`assets/js/hooks/set-input.js`), which is how
  LiveView's own `inputs_for` docs move a row and how the reorder chevrons
  here work. The server casts what it is posted and renders it back; there is
  no path into the params behind the cast, and so no index to get wrong.

  What *is* server state is the evidence: which providers were asked about
  this human, what they said, and which records the operator ticked. That is
  session state exactly as `AmbryWeb.Admin.Evidence` is everywhere else —
  held in socket assigns, never persisted, keyed per card.

  ## Keyed by the row, not by the name

  A card belongs to a credit row, and the name on that row is being typed. So
  the key is the row's `_persistent_id` — the token `inputs_for` already
  round-trips through a hidden input so a list survives reordering — and not
  the name, which changes under it, nor the index, which moves when a row
  above it is dropped.

  ## What differs from the inbox card

  The query box. On the import form a staged person's name and the name worth
  searching for genuinely diverge, so the search carries a box of its own.
  Here the name is an input the operator is looking at, so the button searches
  for whatever it currently says, and revealing the pen-name box is how you
  search for somebody else.
  """

  use AmbryWeb, :html

  import AmbryWeb.Admin.Decisions, only: [credit_people: 1, person_card: 1, person_face: 1]
  import Phoenix.LiveView, only: [put_flash: 3, start_async: 3]

  alias Ambry.Inbox.Draft.Candidate
  alias Ambry.Inbox.Draft.Credit
  alias Ambry.Inbox.Draft.Field
  alias Ambry.Inbox.Draft.PersonDecision
  alias Ambry.Inbox.Draft.SourceRef
  alias Ambry.Metadata.Search, as: MetadataSearch
  alias Ambry.People
  alias AmbryWeb.Admin.Evidence
  alias AmbryWeb.Admin.UploadHelpers

  defstruct evidence: %Evidence{},
            searching?: false,
            expanded?: false,
            own_name?: false,
            query: nil

  @type t :: %__MODULE__{}

  @doc "A fresh form has nobody staged."
  def mount(socket), do: Phoenix.Component.assign(socket, new_people: %{})

  @doc """
  A card's state, or a blank one — a row nobody has asked about still renders
  a card, because the biography box is worth having on its own.
  """
  def state(new_people, key), do: Map.get(new_people, key) || %__MODULE__{}

  @doc """
  The join row a credit is about to hang a human off, or nil.

  The path stops at the **join** — `author_people`, or the narrator itself —
  and deliberately not at the person, because the person is the one thing
  that might not exist: linking somebody the library already has sets
  `person_id`, and the nested person stops being cast. A card that keyed on
  the person vanished at the moment of the pick, taking the way back with it.
  """
  def creating(row_form, path), do: nested(row_form.source, path)

  @doc """
  Whether the operator *said* they meant a new record, rather than having
  typed something nothing matches yet.

  Both post the same name — what is typed is the new record's name either way
  — so a card that watched the typing appeared on the first letter, and did
  so hardest when what the operator was actually doing was searching for an
  existing author. Only one of the two is a decision, and the picker's
  "Create …" row is where it is made (`AmbryWeb.Components.EntityResolver`).
  """
  def chosen(row_form, assoc) do
    case Ecto.Changeset.get_change(row_form.source, assoc) do
      %Ecto.Changeset{params: %{"create" => flag}} -> flag
      _nothing -> nil
    end
  end

  @doc "How many humans a credit's pen name stands for."
  def people_count(row_form) do
    case Ecto.Changeset.get_change(row_form.source, :author) do
      %Ecto.Changeset{} = author -> length(Ecto.Changeset.get_change(author, :author_people, []))
      _nothing -> 0
    end
  end

  @doc "Whether this row has a person to show a card for."
  def carded?(row_form, assoc, path),
    do: chosen(row_form, assoc) == "true" and creating(row_form, path) != nil

  defp nested(changeset, path) do
    Enum.reduce_while(path, changeset, fn step, changeset ->
      case Ecto.Changeset.get_change(changeset, step) do
        %Ecto.Changeset{} = nested -> {:cont, nested}
        [%Ecto.Changeset{} = nested | _rest] -> {:cont, nested}
        _nothing -> {:halt, nil}
      end
    end)
  end

  @doc """
  Whether any row of a credit list is about to create a human.

  What decides whether the section exists at all: a heading over nothing is
  worse than no heading.
  """
  def any?(changeset, assoc, nested_assoc, path) do
    changeset
    |> Ecto.Changeset.get_change(assoc, [])
    |> Enum.any?(&carded?(%{source: &1}, nested_assoc, path))
  end

  @doc """
  The token that identifies a card across renders.

  `inputs_for` puts it in the row's params and renders it as a hidden input,
  so it survives a reorder and a drop; before anything has been posted it
  falls back to the index, which is what it would have been anyway.
  """
  def key(row_form), do: row_form.params["_persistent_id"] || to_string(row_form.index)

  # ── the card ───────────────────────────────────────────────────────────

  attr :row, :any,
    required: true,
    doc:
      "the join row that holds `person_id` and the nested person — `author_people` or `narrator`"

  attr :key, :string, required: true
  attr :state, __MODULE__, required: true
  attr :kind, :atom, required: true, doc: ":author or :narrator"

  attr :credited, :string,
    default: nil,
    doc: "what the credit calls them — the identity's name, never the human's"

  attr :people_count, :integer,
    default: 1,
    doc: "how many humans this pen name stands for — see `group/3`"

  attr :person_index, :integer,
    default: 0,
    doc: "where this human sits behind the pen name — the card's DOM ids key on it"

  attr :list_sort_name, :string,
    default: nil,
    doc: "the `author_people` sort param, for a pen name"

  attr :list_drop_name, :string, default: nil
  attr :removable, :boolean, default: false, doc: "only a pen name's extra people come off"

  @doc """
  One human this form will create — the inbox's own card, on an edit form.

  Nothing is re-drawn here. `AmbryWeb.Admin.Decisions.person_card/1` renders
  a `PersonDecision` and the credit that introduces it, so this builds those
  two out of what an edit form has instead: the nested person changeset for
  the values, and the card's own `Evidence` for the records and the chips
  they propose. A person is a person on both surfaces, so the card is the
  same card — the busy overlay, the photo strip at the size a face is seen,
  the bio box with its preview and its chips, the record list.

  What the card is told is different, and that is the whole difference: with
  an `input_prefix` its three form-bearing controls become plain inputs
  posting into the enclosing form, because an edit form is one form with a
  Save button and forms cannot nest.
  """
  def new_person_card(assigns) do
    person = decision(assigns.row, assigns.key, assigns.state)

    assigns =
      assign(assigns,
        person: person,
        group: group(assigns.credited, assigns.kind, assigns.people_count),
        locals: locals(person)
      )

    ~H"""
    <.person_card
      person={@person}
      group={@group}
      person_index={@person_index}
      input_prefix={@row.name <> "[person]"}
      link_input={@row.name <> "[person_id]"}
      list_sort_name={@list_sort_name}
      list_drop_name={@list_drop_name}
      removable={@removable}
      locals={@locals}
      searching={@state.searching?}
      photos_expanded={@state.expanded?}
      records={@state.evidence.records}
      outcomes={@state.evidence.outcomes}
      query_name={@state.query}
    />
    """
  end

  # People the library already has by this name, which is the outcome worth
  # having: reusing a human is what stops two Andy Weirs sitting in the
  # people list. Skipped once one has been chosen — the row below states it.
  defp locals(%PersonDecision{mode: :link}), do: []

  defp locals(%PersonDecision{} = person) do
    case Field.value(person.name) do
      nil ->
        []

      name ->
        for option <- People.search_people(name, 5),
            String.downcase(option.label) == String.downcase(name) do
          %{
            "id" => option.id,
            "name" => option.label,
            "has_image" => option.image != nil,
            "has_description" => false
          }
        end
    end
  end

  # ── an edit form's answer to the questions the card asks ───────────────

  # The values live in the nested person's params, because they are inputs in
  # the form that will save them. `chosen_key` is derived rather than stored
  # for the same reason: what the field holds IS the answer to "which chip is
  # in use", and a second copy of that answer could disagree with it.
  defp decision(row, key, state) do
    staged = row.params["person"] || %{}
    linked = presence(to_string(row[:person_id].value || ""))
    photo = presence(staged["image_import_url"])
    description = staged["description"]

    %PersonDecision{
      key: key,
      mode: (linked && :link) || :create,
      person_id: linked,
      own_name: state.own_name?,
      name: %Field{value: staged["name"] || row.params["name"]},
      image: field(photo, candidates(state, :image, "image_import_url")),
      description: field(description, candidates(state, :description, "description")),
      sources: Enum.map(Evidence.used_records(state.evidence), &SourceRef.of/1)
    }
  end

  defp field(value, candidates) do
    chosen = Enum.find(candidates, &(present(&1.value) == present(value)))
    %Field{value: value, candidates: candidates, chosen_key: chosen && chosen.key}
  end

  # `Evidence` proposals and draft candidates are the same idea in two
  # vocabularies — a value, a label, a key, and where it came from.
  defp candidates(%__MODULE__{evidence: evidence}, kind, param) do
    if Evidence.any_used?(evidence) do
      for proposal <- Evidence.proposals(evidence, kind) do
        %Candidate{
          key: proposal.key,
          value: proposal.params[param],
          label: Enum.join(proposal.providers, ", "),
          source: proposal.source
        }
      end
    else
      []
    end
  end

  # The card is titled by the credit and asks its pen-name question in the
  # credit's words, so it needs one — built from the row it hangs off. The
  # section and index address a credit inside a draft, which an edit form
  # does not have; every event the card raises from here carries the person's
  # key as well, which is what this surface answers to.
  # The card is titled by the CREDIT and asks its pen-name question in the
  # credit's words: "Foo, a pen name of Bar" only reads that way if the title
  # is the identity's name. Titling it from the person's own name renamed the
  # card letter by letter while the operator typed the very thing it is about.
  # `person_keys` is not decoration here: `Credit.simple?/1` reads its length,
  # and the card asks two things of the answer. A pen name standing for one
  # human is titled by the credit and offers a name box only if you ask for
  # one; a pen name standing for several has no single "their name" to fall
  # back to, so every card opens with its own box and the way back out of the
  # reveal goes away. Claiming one human always gave a freshly added second
  # card a folded box and an offer to be told a name it was already showing.
  defp group(credited, kind, people_count) do
    %{
      credit: %Credit{
        name: credited,
        kind: kind,
        mode: :create,
        person_keys: Enum.map(1..max(people_count, 1)//1, &"person-#{&1}")
      },
      # The card asks "is this pen name more than one person?" of authors and
      # not of narrators, and it asks it of the section — a narrator stays
      # one-to-one with a human by design.
      section: (kind == :author && "work") || "recording",
      index: 0,
      kind: kind
    }
  end

  attr :row, :any, required: true, doc: "the join row that holds the nested person"
  attr :key, :string, required: true

  @doc """
  The person a credit row is about to invent, as a pill beside it.

  The inbox's own reference — enough to recognise who the credit means, and a
  way down to their card. It only ever names one human here, because an edit
  form's pen name has one person behind it until somebody splits it.
  """
  def new_person_pill(assigns) do
    assigns = assign(assigns, :faces, [face(assigns.row, assigns.key)])

    ~H"""
    <.credit_people
      id={"credit-people-#{@key}"}
      faces={@faces}
      section_href="#new-people"
      class="h-10 items-center"
    />
    """
  end

  # The inbox's own answer to "what does this pill say" — the library's name
  # and face where the decision links to somebody, the staged ones where it
  # will create them. Written once, there.
  defp face(row, key), do: person_face(decision(row, key, %__MODULE__{}))

  defp presence(nil), do: nil
  defp presence(value), do: if(String.trim(value) != "", do: value)

  defp present(nil), do: ""
  defp present(value), do: to_string(value)

  defp blank?(nil), do: true
  defp blank?(name), do: String.trim(name) == ""

  # ── the events, shared by every form that renders a card ───────────────

  @doc """
  Every event a card raises, so a form can forward them in one clause.
  """
  def events, do: ~w(research-person person-query toggle-person-source toggle-photos separate-name
         use-credited-name)

  @doc """
  Handles one card event. The form that renders the card owns nothing but the
  assign it lives in.
  """
  def handle_event("research-person", %{"key" => key, "name" => name}, socket) do
    if blank?(name) do
      {:noreply, socket}
    else
      state = state(socket.assigns.new_people, key)

      {:noreply,
       socket
       |> put_state(key, %{state | searching?: true, query: name})
       |> start_async({:person_search, key}, fn ->
         MetadataSearch.people(name)
       end)}
    end
  end

  def handle_event("toggle-person-source", %{"key" => key} = params, socket) do
    %{"source" => source, "id" => id} = params
    state = state(socket.assigns.new_people, key)

    {:noreply,
     put_state(socket, key, %{state | evidence: Evidence.toggle(state.evidence, source, id)})}
  end

  # What the box holds, which stops following the credited name the moment
  # somebody types into it — the name worth searching for is often not the
  # name being credited, which is the whole reason the box is there.
  def handle_event("person-query", %{"key" => key, "value" => query}, socket) do
    state = state(socket.assigns.new_people, key)
    {:noreply, put_state(socket, key, %{state | query: query})}
  end

  def handle_event("toggle-photos", %{"key" => key}, socket) do
    state = state(socket.assigns.new_people, key)
    {:noreply, put_state(socket, key, %{state | expanded?: not state.expanded?})}
  end

  # The pen-name reveal, both ways. `own_name?` is the card's only piece of
  # view state that isn't a form input: it says the human's name is theirs
  # rather than the credit's, and until it is set no name is posted at all,
  # so the person keeps following the credit while it is still being typed.
  def handle_event("separate-name", %{"key" => key}, socket) do
    state = state(socket.assigns.new_people, key)
    {:noreply, put_state(socket, key, %{state | own_name?: true})}
  end

  def handle_event("use-credited-name", %{"key" => key}, socket) do
    state = state(socket.assigns.new_people, key)
    {:noreply, put_state(socket, key, %{state | own_name?: false})}
  end

  @doc """
  Absorbs one card's search results. Records are added, never replaced, so a
  re-search cannot un-tick what the operator chose.
  """
  def handle_async({:person_search, key}, {:ok, result}, socket) do
    state = state(socket.assigns.new_people, key)

    {:noreply,
     put_state(socket, key, %{
       state
       | searching?: false,
         evidence: Evidence.absorb_people(state.evidence, result)
     })}
  end

  def handle_async({:person_search, key}, {:exit, _reason}, socket) do
    state = state(socket.assigns.new_people, key)

    {:noreply,
     socket
     |> put_state(key, %{state | searching?: false})
     |> put_flash(:error, "Searching the providers failed. Try again.")}
  end

  defp put_state(socket, key, state) do
    Phoenix.Component.assign(socket, new_people: Map.put(socket.assigns.new_people, key, state))
  end

  # ── saving ─────────────────────────────────────────────────────────────

  @doc """
  Downloads the photo every new person was given, in the params, before saving.

  The URL is what the chips write and what the form posts; `people.image_path`
  only ever holds a local upload path, so the download happens here — the same
  trade the person form makes, one level down. A save that then fails leaves
  the file behind, which is what has always happened on the person form too.

  The walk is blind to the shape below the association on purpose: an author
  reaches their person through `author_people` and a narrator reaches theirs
  directly, and neither route is worth spelling out twice.
  """
  def import_photos(params, assoc) when is_map(params) do
    case Map.get(params, assoc) do
      rows when is_map(rows) or is_list(rows) -> Map.put(params, assoc, walk(rows))
      _nothing -> params
    end
  end

  defp walk(value) when is_map(value) do
    value
    |> Map.new(fn {key, nested} -> {key, walk(nested)} end)
    |> download()
  end

  defp walk(value) when is_list(value), do: Enum.map(value, &walk/1)
  defp walk(value), do: value

  defp download(%{"image_import_url" => url} = row) when is_binary(url) do
    if blank?(url) do
      Map.delete(row, "image_import_url")
    else
      case UploadHelpers.handle_image_import(url) do
        {:ok, path} -> row |> Map.put("image_path", path) |> Map.delete("image_import_url")
        _failed -> Map.delete(row, "image_import_url")
      end
    end
  end

  defp download(row), do: Map.delete(row, "image_import_url")
end
