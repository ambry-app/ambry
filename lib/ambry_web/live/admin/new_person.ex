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

  import AmbryWeb.Admin.Components

  import AmbryWeb.Admin.Decisions,
    only: [provider_outcomes_row: 1, proposal_chip: 1, record_list: 1, record_row: 1]

  import Phoenix.LiveView, only: [put_flash: 3, start_async: 3]

  alias Ambry.Metadata.Search, as: MetadataSearch
  alias AmbryWeb.Admin.Evidence
  alias AmbryWeb.Admin.UploadHelpers

  defstruct evidence: %Evidence{},
            searching?: false,
            expanded?: false,
            own_name?: false,
            query: nil

  @type t :: %__MODULE__{}

  # Enough to see there are alternatives without the card becoming a contact
  # sheet — the threshold the inbox card folds on, for the same reason.
  @photo_preview 5

  @doc "A fresh form has nobody staged."
  def mount(socket), do: Phoenix.Component.assign(socket, new_people: %{})

  @doc """
  A card's state, or a blank one — a row nobody has asked about still renders
  a card, because the biography box is worth having on its own.
  """
  def state(new_people, key), do: Map.get(new_people, key) || %__MODULE__{}

  @doc """
  The nested person changeset a credit row is about to create, or nil.

  `EntityRef.cast_new/4` casts a nested record only for a row that points at
  nothing, so the presence of the nested chain *is* the answer: a credit
  linked to an existing author, or a new pen name for a person the library
  already has, reaches no person and gets no card.
  """
  def creating(row_form, path), do: nested(row_form.source, path)

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
    |> Enum.any?(&(nested(&1, path) != nil))
  end

  @doc """
  The token that identifies a card across renders.

  `inputs_for` puts it in the row's params and renders it as a hidden input,
  so it survives a reorder and a drop; before anything has been posted it
  falls back to the index, which is what it would have been anyway.
  """
  def key(row_form), do: row_form.params["_persistent_id"] || to_string(row_form.index)

  # ── the card ───────────────────────────────────────────────────────────

  attr :form, :any, required: true, doc: "the nested person form"
  attr :key, :string, required: true
  attr :state, __MODULE__, required: true
  attr :kind, :atom, required: true, doc: ":author or :narrator — words only"

  @doc """
  One human this form will create, and everything anyone knows about them.
  """
  def new_person_card(assigns) do
    photo = assigns.form.params["image_import_url"]
    description = assigns.form[:description].value

    assigns =
      assign(assigns,
        name: assigns.form[:name].value,
        photo: photo,
        photos: chosen(proposals(assigns.state, :image), "image_import_url", photo),
        bios: chosen(proposals(assigns.state, :description), "description", description),
        records: assigns.state.evidence.records,
        outcomes: assigns.state.evidence.outcomes
      )

    ~H"""
    <div
      id={"new-person-#{@key}"}
      phx-hook="set-input"
      class="space-y-3 rounded-lg bg-zinc-900 p-4"
      data-role="new-person"
      data-person-key={@key}
    >
      <div class="flex items-baseline justify-between gap-2 pl-3">
        <.microlabel>New person · {@name || "unnamed"}</.microlabel>

        <button
          :if={!@state.own_name?}
          type="button"
          phx-click="reveal-person-name"
          phx-value-key={@key}
          class="text-xs text-zinc-400 underline"
        >
          {reveal_words(@kind)}
        </button>
      </div>

      <%!-- The exception, revealed. Left alone the human is named by the
            credit and no name is posted at all, which is what keeps the two
            in step while the credit is still being typed: a box on every card
            froze the person's name at whatever the credit said one keystroke
            in. --%>
      <div :if={@state.own_name?} class="space-y-1">
        <p class="pl-3 text-xs text-zinc-400">{alias_words(@kind)}</p>
        <.input field={@form[:name]} placeholder="the person's real name" />
      </div>

      <div class="flex items-center gap-3 pl-3">
        <.image_with_size
          :if={@photo}
          id={"new-person-#{@key}-photo"}
          src={proxied_remote_image_url(@photo)}
          class="h-12 w-12 flex-none rounded-full object-cover object-top"
        />
        <span
          :if={!@photo}
          class="h-12 w-12 flex-none rounded-full border border-dashed border-zinc-700"
        />

        <%!-- The chosen face travels as the URL the person form's own import
              machinery takes, and is downloaded by the save that creates
              them. Nothing is fetched while the operator is still deciding. --%>
        <input type="hidden" name={@form.name <> "[image_import_url]"} value={@photo} />

        <.button
          type="button"
          color={:zinc}
          phx-click="research-person"
          phx-value-key={@key}
          phx-value-name={@name}
          disabled={@state.searching? or blank?(@name)}
        >
          {search_words(@state)}
        </.button>
      </div>

      <div :if={@state.evidence.searched?} class="space-y-2">
        <.microlabel class="block pl-3">Provider records</.microlabel>

        <p :if={@state.query && @state.query != @name} class="pl-3 text-xs text-zinc-400">
          Records for "{@state.query}".
        </p>

        <.provider_outcomes_row outcomes={@outcomes} retryable={false} />

        <%!-- Nothing found is a normal outcome, not a failure: plenty of
              narrators are in no database at all. --%>
        <p :if={@records == [] and !@state.searching?} class="pl-3 text-xs text-zinc-400">
          Nobody by that name is in any provider we can ask. A name is all it takes to make a
          person.
        </p>

        <.record_list records={@records} used={&Evidence.used?(@state.evidence, &1)}>
          <:row :let={record}>
            <.record_row
              record={record}
              event="toggle-person-source"
              person_key={@key}
              used={Evidence.used?(@state.evidence, record)}
            />
          </:row>
        </.record_list>
      </div>

      <%!-- Circular and at the size they will be seen, because the decision
            is whether a face survives a circular crop. --%>
      <div :if={@photos != []} class="grid-cols-[4rem_minmax(0,1fr)] grid items-start gap-x-2 pl-3">
        <.microlabel class="pt-1">Photos</.microlabel>

        <div class="flex flex-wrap items-center gap-2">
          <.proposal_chip
            :for={photo <- shown_photos(@photos, @state.expanded?)}
            chosen={photo.chosen}
            title={photo.display}
            shape="circle"
            data-set-input={@form.name <> "[image_import_url]"}
            data-set-value={photo.params["image_import_url"]}
          >
            <.image_with_size
              id={"new-person-#{@key}-photo-#{photo.key}"}
              src={proxied_remote_image_url(photo.params["image_import_url"])}
              class="h-16 w-16 rounded-full object-cover object-top"
            />
          </.proposal_chip>

          <button
            :if={length(@photos) > photo_preview()}
            type="button"
            phx-click="toggle-person-photos"
            phx-value-key={@key}
            class="text-xs text-zinc-400 underline"
          >
            {if @state.expanded?, do: "show fewer", else: "show all #{length(@photos)} photos"}
          </button>

          <button
            :if={@photo}
            type="button"
            data-set-input={@form.name <> "[image_import_url]"}
            data-set-value=""
            class="self-center rounded-sm border border-dashed border-zinc-600 px-2 py-1 text-xs text-zinc-400 hover:border-zinc-500 hover:text-zinc-200"
          >
            no photo
          </button>
        </div>
      </div>

      <%!-- A provider's blurb is a starting point you tweak, not a thing you
            take or leave, so it is the same editable box with the same chips
            under it that every other description on these forms has. --%>
      <div class="space-y-2">
        <.input type="textarea" field={@form[:description]} label="Biography" />

        <div :if={@bios != []} class="flex flex-wrap items-center gap-2 pl-3">
          <.microlabel>Proposed</.microlabel>

          <.proposal_chip
            :for={bio <- @bios}
            chosen={bio.chosen}
            title={bio.params["description"]}
            data-set-input={@form[:description].name}
            data-set-value={bio.params["description"]}
          >
            <span class="truncate">{bio.display}</span>
            <span class="text-zinc-500">{Enum.join(bio.providers, ", ")}</span>
          </.proposal_chip>
        </div>
      </div>
    </div>
    """
  end

  defp proposals(%__MODULE__{evidence: evidence}, field) do
    if Evidence.any_used?(evidence), do: Evidence.proposals(evidence, field), else: []
  end

  # One param decides it here, not the whole set `Curation.mark_chosen/2`
  # compares: a chip writes one input, and the rest of what the proposal
  # carries is bookkeeping the card doesn't render.
  defp chosen(proposals, key, current) do
    Enum.map(proposals, &Map.put(&1, :chosen, present(&1.params[key]) == present(current)))
  end

  defp present(nil), do: ""
  defp present(value), do: to_string(value)

  defp shown_photos(photos, true), do: photos
  defp shown_photos(photos, false), do: Enum.take(photos, @photo_preview)

  defp photo_preview, do: @photo_preview

  defp search_words(%__MODULE__{searching?: true}), do: "Searching…"
  defp search_words(%__MODULE__{evidence: %{searched?: true}}), do: "Search again"
  defp search_words(_state), do: "Search providers"

  defp reveal_words(:narrator), do: "This is a stage name"
  defp reveal_words(_author), do: "This is a pen name"

  defp alias_words(:narrator), do: "A stage name of"
  defp alias_words(_author), do: "A pen name of"

  defp blank?(nil), do: true
  defp blank?(name), do: String.trim(name) == ""

  # ── the events, shared by every form that renders a card ───────────────

  @doc """
  Every event a card raises, so a form can forward them in one clause.
  """
  def events, do: ~w(research-person toggle-person-source toggle-person-photos reveal-person-name)

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

  def handle_event("toggle-person-photos", %{"key" => key}, socket) do
    state = state(socket.assigns.new_people, key)
    {:noreply, put_state(socket, key, %{state | expanded?: not state.expanded?})}
  end

  def handle_event("reveal-person-name", %{"key" => key}, socket) do
    state = state(socket.assigns.new_people, key)
    {:noreply, put_state(socket, key, %{state | own_name?: true})}
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
