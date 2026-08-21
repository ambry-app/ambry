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
  alias Phoenix.LiveView.JS

  defstruct evidence: %Evidence{},
            searching?: false,
            expanded?: false,
            own_name?: false,
            curated?: false,
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

  @doc "How many humans a credit's pen name stands for."
  def people_count(row_form) do
    case Ecto.Changeset.get_change(row_form.source, :author) do
      %Ecto.Changeset{} = author -> length(Ecto.Changeset.get_change(author, :author_people, []))
      _nothing -> 0
    end
  end

  @doc """
  Whether this row has a person to show a card for.

  **The row brings a person of its own.** Three things have to be true and
  this one sentence is all three: the credit names something the library
  doesn't have (a row pointing at an author it *does* casts nothing —
  `Ambry.Ecto.EntityRef`), the name is a decision rather than half a word
  being typed (the picker only tells the form once the box is left), and the
  human behind it is somebody to make rather than somebody to reuse — a join
  that already says which person it means carries no nested person at all
  (`Ambry.People.AuthorPerson.credited_changeset/3`).

  Asked of the params rather than of the changes, which is what keeps the
  card up when the operator links a library person **from** it: the pick sets
  `person_id`, the nested person stops being cast, and a card reading changes
  would vanish at the moment of the pick and take the way back with it. The
  inputs are still on the page and still post, so the params still say the
  card is there.

  This used to want a separate "the operator clicked Create" flag, because
  the picker announced every keystroke. Everything that staged a credit
  *without* the picker then had to remember to set it, and the provider chips
  didn't — an accepted narrator got no card at all (operator, 2026-08-21).
  """
  def carded?(row_form, path) do
    match?(%Ecto.Changeset{params: %{"person" => _person}}, creating(row_form, path))
  end

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
  def any?(changeset, assoc, path) do
    changeset
    |> Ecto.Changeset.get_change(assoc, [])
    |> Enum.any?(&carded?(%{source: &1}, path))
  end

  @doc """
  Every card this credit list renders, as `{key, the name it credits}`.

  What "Search all" needs and nothing else has: the cards are rendered by
  `inputs_for` inside the form, and a control *above* them has no walk of its
  own. Same walk `any?/3` makes, carrying the two things a search takes.

  The key mirrors what the templates build — suffixed by the person's index
  where the join is a list, because a pen name can stand for several humans
  and each has a card. The list is the last step of `path` in both forms.
  """
  def cards(changeset, assoc, path) do
    changeset
    |> Ecto.Changeset.get_change(assoc, [])
    |> Enum.with_index()
    |> Enum.flat_map(fn {row, index} -> row_cards(row, index, path) end)
  end

  defp row_cards(row, index, [identity | _rest] = path) do
    row_form = %{source: row, params: row.params}

    if carded?(row_form, path) do
      key = row.params["_persistent_id"] || to_string(index)

      name =
        Ecto.Changeset.get_change(row, identity)
        |> then(&(&1 && Ecto.Changeset.get_field(&1, :name)))

      case joined(row, path) do
        {:list, count} -> for at <- 0..(count - 1)//1, do: {"#{key}-#{at}", name}
        :one -> [{key, name}]
      end
    else
      []
    end
  end

  # Whether the card hangs off one join or off a list of them — a stage name
  # is one human by design, a pen name may be several.
  defp joined(changeset, path) do
    Enum.reduce_while(path, :one, fn step, _shape ->
      case Ecto.Changeset.get_change(changeset, step) do
        %Ecto.Changeset{} = nested -> {:cont, {:one, nested}}
        [_ | _] = nested -> {:cont, {:list, nested}}
        _nothing -> {:halt, :one}
      end
    end)
    |> case do
      {:list, rows} -> {:list, length(rows)}
      _one -> :one
    end
  end

  @doc """
  Searches for every card that has not been searched for yet.

  Ten chips clicked is ten new people, and finding out about them was ten
  more clicks in ten different places (operator, 2026-08-21). Chained
  `JS.push/3` rather than a new event: pressing them all IS the feature, and
  each card's own handler already knows what to do with one.

  Cards that have already been asked about are left out — a re-search is a
  per-card decision, and the button is about the ones nobody has asked about.
  """
  def search_all(cards, new_people) do
    cards
    |> Enum.reject(fn {key, name} -> blank?(name) or searched?(new_people, key) end)
    |> Enum.reduce(%JS{}, fn {key, name}, js ->
      JS.push(js, "research-person", value: %{"key" => key, "name" => name})
    end)
  end

  @doc "How many cards `search_all/2` would ask about."
  def searchable(cards, new_people) do
    Enum.count(cards, fn {key, name} -> not (blank?(name) or searched?(new_people, key)) end)
  end

  defp searched?(new_people, key) do
    state = state(new_people, key)
    state.searching? or state.evidence.searched?
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
      at={"card-" <> @key}
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
    photos = candidates(state, :image, "image_import_url")
    bios = candidates(state, :description, "description")
    photo = presence(answered(staged, "image_import_url", photos))
    description = answered(staged, "description", bios)

    %PersonDecision{
      key: key,
      mode: (linked && :link) || :create,
      person_id: linked,
      own_name: state.own_name?,
      name: %Field{value: staged["name"] || row.params["name"]},
      image: field(photo, photos),
      description: field(description, bios),
      sources: Enum.map(Evidence.used_records(state.evidence), &SourceRef.of/1),
      # What lights "None of these", which is the card's reading of "they
      # touched the evidence and left nothing ticked" — the same reading the
      # import form makes. Records arrive ticked here, so an untouched card
      # with nothing used has simply found nobody, and must not claim to have
      # been answered.
      evidence_curated: state.curated?
    }
  end

  # **A question nobody has answered is answered by the best record.**
  #
  # A ticked record only ever *offered* a face and a biography here, so
  # finishing a person meant clicking two more chips per human — and the
  # operator who ticked the record and saved got a person with a name and
  # nothing else, which is the exact asymmetry `EDIT_PARITY_PLAN.md` was
  # opened to close. An import takes the best record's answer for both and
  # leaves the rest one click away (`Draft.Seed.scalar/2`, `alternatives:
  # true`); so does this.
  #
  # **Absent is unanswered; present-and-empty is an answer.** The card's
  # controls are inputs, so once one has rendered every later post carries
  # it — which means "no photo" and a cleared biography arrive as `""` and
  # are left exactly as they are. Only a person nobody has posted anything
  # about yet has no key at all, and that is the one this fills.
  defp answered(staged, key, candidates) do
    case Map.fetch(staged, key) do
      {:ok, value} -> value
      :error -> best(candidates)
    end
  end

  # Evidence orders proposals by the score of the record that made them, so
  # the first is the best record's answer.
  defp best([%Candidate{value: value} | _rest]), do: value
  defp best(_none), do: nil

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
      section_href="#people"
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
         use-credited-name uncatalogued-person)

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
     put_state(socket, key, %{
       state
       | curated?: true,
         evidence: Evidence.toggle(state.evidence, source, id)
     })}
  end

  # The photo and the biography are inputs, and the button blanks them on the
  # client the way the chips fill them (`assets/js/hooks/set-input.js`); what
  # is left for the server is the evidence itself.
  def handle_event("uncatalogued-person", %{"key" => key}, socket) do
    state = state(socket.assigns.new_people, key)

    {:noreply,
     put_state(socket, key, %{state | curated?: true, evidence: Evidence.use_none(state.evidence)})}
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

  The ones actually **about** the name searched for arrive ticked, and the
  best of them answers the photo and biography the operator hasn't answered
  — see `Evidence.absorb_people/3` and `answered/3`. Person search is
  recall-first, so the rest are listed and left alone.
  """
  def handle_async({:person_search, key}, {:ok, result}, socket) do
    state = state(socket.assigns.new_people, key)

    {:noreply,
     put_state(socket, key, %{
       state
       | searching?: false,
         evidence: Evidence.absorb_people(state.evidence, result, about: state.query)
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

  **A download that fails stops the save.** It used to drop the URL and carry
  on, so a form that saved perfectly well created a person with no face and
  said nothing about it — indistinguishable, from the operator's side, from a
  photo that was never chosen. The recording's own cover has always flashed
  in that case; so does a person's now, naming the ones that failed.
  """
  def import_photos(params, assoc) when is_map(params) do
    case Map.get(params, assoc) do
      rows when is_map(rows) or is_list(rows) ->
        case walk(rows, []) do
          {walked, []} -> {:ok, Map.put(params, assoc, walked)}
          {_walked, failed} -> {:error, {:failed_photos, Enum.reverse(failed)}}
        end

      _nothing ->
        {:ok, params}
    end
  end

  @doc """
  What to tell the operator when a chosen photo could not be fetched.
  """
  def photos_error([_one]),
    do: "Couldn't download the photo chosen for a new person. Choose another, or clear it."

  def photos_error(urls),
    do:
      "Couldn't download #{length(urls)} of the photos chosen for new people. " <>
        "Choose others, or clear them."

  defp walk(value, failed) when is_map(value) do
    {pairs, failed} =
      Enum.map_reduce(value, failed, fn {key, nested}, failed ->
        {walked, failed} = walk(nested, failed)
        {{key, walked}, failed}
      end)

    pairs |> Map.new() |> download(failed)
  end

  defp walk(value, failed) when is_list(value), do: Enum.map_reduce(value, failed, &walk/2)
  defp walk(value, failed), do: {value, failed}

  defp download(%{"image_import_url" => url} = row, failed) when is_binary(url) do
    if blank?(url) do
      {Map.delete(row, "image_import_url"), failed}
    else
      case UploadHelpers.handle_image_import(url) do
        {:ok, path} ->
          {row |> Map.put("image_path", path) |> Map.delete("image_import_url"), failed}

        _failed ->
          {Map.delete(row, "image_import_url"), [url | failed]}
      end
    end
  end

  defp download(row, failed), do: {Map.delete(row, "image_import_url"), failed}
end
