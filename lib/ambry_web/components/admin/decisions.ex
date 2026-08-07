defmodule AmbryWeb.Admin.Decisions do
  @moduledoc """
  The building blocks of a staged import: one decision, and one entity
  resolution.

  These are deliberately general rather than inbox-specific. Today's
  book/media/person forms already do a cruder version of both — the
  provider-import forms' checkbox-merge rows are `decision_row/1` in embryo,
  and their all-or-nothing "use all authors" grouping is exactly the per-item
  selection defect this fixes. The intent is that those surfaces converge here
  whenever they're next touched, and that "a draft over an existing record,
  with no file placement" ends up being the same form.
  """

  use Phoenix.Component
  use AmbryWeb, :verified_routes

  import AmbryWeb.Admin.Components, only: [badge: 1]
  import AmbryWeb.CoreComponents

  alias Ambry.Inbox.Draft.Credit
  alias Ambry.Inbox.Draft.Field
  alias Ambry.Inbox.Draft.PersonRef
  alias Ambry.Inbox.Draft.SeriesLink

  attr :outcomes, :list, required: true
  attr :level, :string, default: nil
  attr :retrying, :any, default: nil

  @doc """
  What each provider said when asked — including the ones that couldn't
  answer.

  Without this, a provider that errors is indistinguishable from one that
  genuinely found nothing: both contribute zero candidates and say nothing
  about why. That's how an enabled-but-rate-limited source looks like it was
  never consulted.
  """
  def provider_outcomes_row(assigns) do
    ~H"""
    <div :if={@outcomes != []} class="flex flex-wrap items-center gap-2" data-role="provider-outcomes">
      <span class="text-xs dark:text-zinc-500">Asked:</span>

      <span
        :for={outcome <- @outcomes}
        :if={outcome["status"] != "failed"}
        class="rounded-sm border border-zinc-300 px-2 py-0.5 text-xs dark:border-zinc-700"
      >
        {outcome["name"]}: {outcome["count"]}
      </span>

      <%!-- A provider that was rate-limited during matching used to cost this
            item its records until somebody re-ran the whole match. The chip is
            the retry. --%>
      <button
        :for={outcome <- @outcomes}
        :if={outcome["status"] == "failed"}
        type="button"
        phx-click="retry-provider"
        phx-value-level={@level}
        phx-value-provider={outcome["id"]}
        disabled={@retrying == outcome["id"]}
        title={outcome["reason"]}
        class="rounded-sm border border-red-500 px-2 py-0.5 text-xs text-red-600 disabled:opacity-50"
      >
        {outcome["name"]}: {if @retrying == outcome["id"],
          do: "asking again…",
          else: "couldn't be reached — retry"}
      </button>
    </div>
    """
  end

  attr :query, :string, default: nil
  attr :fields, :map, default: %{}

  @doc """
  The search that produced this level's candidates.

  Shown because the first question anyone asks a bad match is "what did you
  even search for?" — and the answer is not obvious: the hints come from tags
  first and the release name second, so a wrong author in an ID3 frame sends
  the whole level somewhere strange with no visible cause.
  """
  def query_row(assigns) do
    ~H"""
    <div :if={@query || @fields != %{}} class="text-xs dark:text-zinc-500" data-role="query">
      <span>Searched for</span>
      <span :for={{key, value} <- ordered_fields(@fields)} class="ml-1">
        <span class="dark:text-zinc-600">{key}:</span>
        <span class="font-mono dark:text-zinc-400">{value}</span>
      </span>
      <span :if={@fields == %{}} class="font-mono ml-1 dark:text-zinc-400">{@query}</span>
      <p class="italic">
        A provider whose narrow search comes back empty may widen it, so what matched can be broader
        than this.
      </p>
    </div>
    """
  end

  # Same order every time, and the order the query is actually built in.
  defp ordered_fields(fields) do
    for key <- ~w(title author narrator keywords),
        value = fields[key],
        value not in [nil, ""],
        do: {key, value}
  end

  attr :record, :map, required: true
  attr :used, :boolean, required: true
  attr :level, :string, required: true
  attr :working, :boolean, default: false

  @doc """
  One provider record, and whether it counts.

  Not an identity — evidence. Hardcover and rreading-glasses both holding a
  record of one book is the normal case, not a duplicate to clean up, and each
  knows things the other doesn't. Ticking both is how the description comes
  from one and the cover from the other.
  """
  def record_row(assigns) do
    ~H"""
    <label
      class={[
        "flex cursor-pointer items-start gap-3 rounded-sm border p-2",
        @used && "border-brand bg-brand/5 dark:border-brand-dark dark:bg-brand-dark/10",
        !@used && "border-zinc-300 hover:border-zinc-400 dark:border-zinc-700 dark:hover:border-zinc-500"
      ]}
      data-role="record"
      data-used={@used && "true"}
    >
      <input
        type="checkbox"
        checked={@used}
        phx-click="toggle-source"
        phx-value-level={@level}
        phx-value-source={@record["source"]}
        phx-value-id={@record["id"]}
        class="mt-1 h-4 w-4 flex-none rounded-sm"
      />
      <div class="min-w-0 flex-grow">
        <p class="truncate text-sm">{candidate_title(@record)}</p>
        <p class="truncate text-xs dark:text-zinc-500">{candidate_facts(@record)}</p>
      </div>
      <span :if={@working} class="flex-none pt-0.5 text-xs dark:text-zinc-400">
        fetching…
      </span>
      <span :if={!@working && @record["score"]} class="flex-none pt-0.5 text-xs dark:text-zinc-600">
        {round(@record["score"] * 100)}%
      </span>
    </label>
    """
  end

  attr :book, :map, required: true
  attr :linked, :boolean, required: true

  @doc """
  An existing Book this release might be another edition of.

  Kept well away from the provider records, because it answers a different
  question. Linking creates nothing, inherits the book's curation and adds an
  alternate edition; importing a provider record creates a Book. Ranking the
  two together made the form ask one question that was really two.
  """
  def local_book_row(assigns) do
    ~H"""
    <div
      class={[
        "flex items-start gap-3 rounded-sm border p-3",
        @linked && "border-brand bg-brand/5 dark:border-brand-dark dark:bg-brand-dark/10",
        !@linked && "border-zinc-300 dark:border-zinc-700"
      ]}
      data-role="local-book"
      data-linked={@linked && "true"}
    >
      <div class="min-w-0 flex-grow">
        <p class="truncate text-sm font-semibold">{candidate_title(@book)}</p>
        <p class="truncate text-xs dark:text-zinc-500">{candidate_facts(@book)}</p>
      </div>

      <button
        :if={!@linked}
        type="button"
        phx-click="link-book"
        phx-value-id={@book["id"]}
        class="flex-none rounded-sm border border-zinc-300 px-2 py-1 text-xs dark:border-zinc-700"
      >
        Yes — another edition of this
      </button>

      <span :if={@linked} class="flex-none text-xs dark:text-zinc-500">using this book</span>
    </div>
    """
  end

  attr :level, :string, required: true
  attr :fields, :map, required: true
  attr :running, :boolean, default: false

  @doc """
  An editable version of the search that produced these records.

  The stored candidate list makes "show me the alternatives" free; this is for
  the case the list exists for — the right answer isn't in it at all, usually
  because a wrong tag sent the search somewhere strange.
  """
  def research_form(assigns) do
    ~H"""
    <form
      id={"research-#{@level}"}
      phx-submit="research"
      class="flex flex-wrap items-end gap-2"
    >
      <input type="hidden" name="level" value={@level} />

      <label class="text-xs dark:text-zinc-500">
        title
        <input
          type="text"
          name="title"
          value={@fields["title"]}
          class="mt-1 block rounded-sm border-zinc-300 text-sm dark:border-zinc-600 dark:bg-zinc-800"
        />
      </label>

      <label class="text-xs dark:text-zinc-500">
        author
        <input
          type="text"
          name="author"
          value={@fields["author"]}
          class="mt-1 block rounded-sm border-zinc-300 text-sm dark:border-zinc-600 dark:bg-zinc-800"
        />
      </label>

      <label :if={@level == "recording"} class="text-xs dark:text-zinc-500">
        narrator
        <input
          type="text"
          name="narrator"
          value={@fields["narrator"]}
          class="mt-1 block rounded-sm border-zinc-300 text-sm dark:border-zinc-600 dark:bg-zinc-800"
        />
      </label>

      <button
        type="submit"
        disabled={@running}
        class="rounded-sm border border-zinc-300 px-2 py-1 text-xs disabled:opacity-50 dark:border-zinc-700"
      >
        {if @running, do: "Searching…", else: "Search again"}
      </button>
    </form>
    """
  end

  @doc "A candidate's headline: what it is."
  def candidate_title(candidate) do
    [candidate["title"], candidate["authors"] && Enum.join(candidate["authors"], ", ")]
    |> Enum.reject(&(&1 in [nil, "", []]))
    |> Enum.join(" — ")
  end

  @doc """
  A candidate's distinguishing facts, in one line.

  Narrator and year lead because they are what tell two recordings of one work
  apart — the whole reason the recording level exists.
  """
  def candidate_facts(candidate) do
    [
      candidate["narrators"] not in [nil, []] &&
        "read by #{Enum.join(candidate["narrators"], ", ")}",
      year(candidate["published"]),
      candidate["publisher"],
      series_line(candidate["series"]),
      candidate["asin"],
      candidate_origin(candidate),
      candidate["also_from"] not in [nil, []] &&
        "also #{Enum.join(List.wrap(candidate["also_from"]), ", ")}"
    ]
    |> Enum.filter(&is_binary/1)
    |> Enum.join(" · ")
  end

  defp year(nil), do: nil
  defp year(published) when is_binary(published), do: String.slice(published, 0, 4)
  defp year(_other), do: nil

  # Series arrive as `%{"name", "number"}` now and as bare strings in matches
  # stored before that; both render.
  defp series_line(nil), do: nil
  defp series_line([]), do: nil

  defp series_line(series) when is_list(series) do
    Enum.map_join(series, ", ", fn
      %{"name" => name, "number" => number} when number not in [nil, ""] -> "#{name} ##{number}"
      %{"name" => name} -> name
      name when is_binary(name) -> name
    end)
  end

  defp series_line(_other), do: nil

  @doc "Where a candidate came from, in words rather than an id."
  def candidate_origin(%{"source" => "local"}), do: "already in the library"
  def candidate_origin(%{"provider_name" => name}) when is_binary(name), do: name
  def candidate_origin(%{"source" => "provider:" <> id}), do: id
  def candidate_origin(_candidate), do: nil

  attr :label, :string, required: true
  attr :section, :string, required: true
  attr :name, :atom, required: true
  attr :form, :any, required: true, doc: "the enclosing work/recording form"
  attr :field, Field, required: true, doc: "the staged decision itself"
  attr :type, :string, default: "text"
  attr :options, :list, default: nil
  attr :placeholder, :string, default: nil
  attr :hint, :string, default: nil
  attr :preview, :boolean, default: false
  attr :embedded_src, :string, default: nil, doc: "where the file's own art can be seen"

  @doc """
  One scalar decision: what the sources proposed, what it will be, and where
  that came from.

  The candidates stay visible after one is chosen. Hiding them would make the
  choice feel final when the whole point is that it's reviewable — and
  re-querying to see an alternative you already had is the cost the ranked
  candidate list exists to avoid.
  """
  def decision_row(assigns) do
    ~H"""
    <div class="space-y-1">
      <div class="flex items-center gap-2">
        <.label>{@label}</.label>

        <.badge
          :if={!@field.approved}
          color={elem(state_words(Field.state(@field)), 1)}
          class="text-xs"
        >
          {elem(state_words(Field.state(@field)), 0)}
        </.badge>

        <span :if={@field.approved && @field.source} class="text-xs dark:text-zinc-500">
          from {source_words(@field.source)}
        </span>

        <span :if={@field.approved && is_nil(@field.source)} class="text-xs dark:text-zinc-500">
          left empty on purpose
        </span>
      </div>

      <p :if={@hint} class="text-xs italic dark:text-zinc-500">{@hint}</p>

      <div class="flex items-start gap-3">
        <%!-- A URL in a text box is not a cover. Seeing the image is the only
              way to catch a provider that returned the wrong edition's art —
              and its dimensions, because a thumbnail and a full-size cover
              look identical here and only one of them is worth importing.
              Routed through the admin proxy like every other import preview,
              or tracking protection blocks the provider CDN. --%>
        <.image_with_size
          :if={@preview && preview_src(@field.value, @embedded_src)}
          id={"#{@section}-#{@name}"}
          src={preview_src(@field.value, @embedded_src)}
          class="h-24 w-24 flex-none rounded-sm object-cover"
        />

        <div class="min-w-0 flex-grow">
          <.inputs_for :let={decision} field={@form[@name]}>
            <.input
              :if={@type == "select"}
              field={decision[:value]}
              type="select"
              options={@options}
            />
            <.input
              :if={@type != "select"}
              field={decision[:value]}
              type={@type}
              placeholder={@placeholder}
            />
          </.inputs_for>
        </div>
      </div>

      <div :if={@field.candidates != []} class="flex flex-wrap items-center gap-2 pt-1">
        <span class="text-xs dark:text-zinc-500">Proposed:</span>

        <button
          :for={candidate <- @field.candidates}
          type="button"
          phx-click="choose-field"
          phx-value-section={@section}
          phx-value-field={@name}
          phx-value-key={candidate.key}
          class={[
            "rounded-sm border px-2 py-1 text-left text-xs",
            Field.chose?(@field, candidate) && "border-brand dark:border-brand-dark",
            !Field.chose?(@field, candidate) && "border-zinc-300 dark:border-zinc-700"
          ]}
        >
          <span class="dark:text-zinc-500">{candidate.label || source_words(candidate.source)}:</span>
          <span :if={!@preview}>{truncate(candidate.value)}</span>

          <%!-- Choosing between two covers by URL is choosing blind. --%>
          <.image_with_size
            :if={@preview && preview_src(candidate.value, @embedded_src)}
            id={"#{@section}-#{@name}-#{candidate.key}"}
            src={preview_src(candidate.value, @embedded_src)}
            class="mt-1 h-20 w-20 rounded-sm object-cover"
          />
        </button>

        <%!-- Choosing "none" is an approval, not an omission. It's what makes
              "every piece is settled" reachable on a record with optional
              fields nobody filled in. --%>
        <button
          :if={!@field.required}
          type="button"
          phx-click="waive-field"
          phx-value-section={@section}
          phx-value-field={@name}
          class="rounded-sm border border-zinc-300 px-2 py-1 text-xs dark:border-zinc-700"
        >
          None
        </button>
      </div>
    </div>
    """
  end

  attr :credit, Credit, required: true
  attr :index, :integer, required: true
  attr :section, :string, required: true
  attr :identities, :list, required: true
  attr :people, :list, required: true
  attr :verb, :string, required: true, doc: ~s(the visible label — "Written by")
  attr :reveal, :string, required: true, doc: ~s(the unfold link — "This is a pen name")
  attr :backing, :string, required: true, doc: ~s(the unfolded label — "Pen name of")
  attr :expanded, :boolean, required: true
  attr :kind, :atom, required: true, doc: ":author or :narrator"
  attr :sharing, :map, default: %{}, doc: "PersonRef key => the credits behind it"
  attr :found, :map, default: %{}, doc: "person index => %{photos:, bios:, searching:}"
  attr :photos_expanded, :map, default: %{}, doc: "person index => whether all photos show"

  @doc """
  One credit, resolved to an identity.

  ## One control by default

  A credited name IS an identity. How many humans stand behind it is a fact
  about the *person* — not about this book — and no provider reports it, so
  asking on every import buried the two cases where the answer is interesting
  under dozens where it isn't. The person layer is therefore folded away
  behind "This is a pen name" / "This is a stage name", and unfolds itself
  whenever the credit is anything but the 1:1 default (`Credit.simple?/1`).

  ## The name is editable

  A provider's spelling is a proposal like any other. Without a box to
  overrule it, "David Wong" could only be imported as a person called David
  Wong — the human is Jason Pargin, and that import is one author plus one
  differently-named person, which is now two edits rather than impossible.

  A link decision always targets an identity, never a Person. That is the
  generalized fix for the pen-name bug where matching found a Person and
  linked its first identity.
  """
  def credit_row(assigns) do
    ~H"""
    <div class="space-y-2 rounded-sm border border-zinc-300 p-3 dark:border-zinc-700">
      <div class="flex items-center justify-between gap-2">
        <div class="flex min-w-0 items-center gap-2">
          <.icon
            :if={Credit.resolved?(@credit)}
            name="fa-circle-check"
            class="text-brand h-4 w-4 flex-none dark:text-brand-dark"
          />
          <.label class="text-xs">{@verb}</.label>

          <.badge
            :if={!Credit.resolved?(@credit)}
            color={elem(state_words(Credit.state(@credit)), 1)}
            class="text-xs"
          >
            {elem(state_words(Credit.state(@credit)), 0)}
          </.badge>

          <span :if={@credit.source} class="text-xs dark:text-zinc-500">
            from {source_words(@credit.source)}
          </span>
        </div>

        <div class="flex flex-none items-center gap-2">
          <button
            :if={!@credit.approved}
            type="button"
            phx-click="approve-credit"
            phx-value-section={@section}
            phx-value-index={@index}
            phx-value-approved="true"
            class="rounded-sm border border-zinc-300 px-2 py-1 text-xs dark:border-zinc-700"
          >
            Confirm
          </button>

          <button
            type="button"
            phx-click="remove-credit"
            phx-value-section={@section}
            phx-value-index={@index}
            title="This recording isn't by them"
          >
            <.icon name="fa-xmark" class="h-4 w-4 cursor-pointer hover:text-red-600" />
          </button>
        </div>
      </div>

      <form
        id={"credit-#{@section}-#{@index}-identity"}
        phx-change="credit-change"
        class="flex flex-wrap items-center gap-2"
      >
        <input type="hidden" name="section" value={@section} />
        <input type="hidden" name="index" value={@index} />

        <select
          name="identity_id"
          class="rounded-sm border-zinc-300 text-sm dark:border-zinc-600 dark:bg-zinc-800"
        >
          <option value="">Create new…</option>
          <option
            :for={{name, id} <- @identities}
            value={id}
            selected={@credit.mode == :link and @credit.identity_id == id}
          >
            {name}
          </option>
        </select>

        <input
          :if={@credit.mode == :create}
          type="text"
          name="name"
          value={@credit.name}
          placeholder="name"
          class="min-w-0 flex-grow rounded-sm border-zinc-300 text-sm dark:border-zinc-600 dark:bg-zinc-800"
        />

        <span :if={@credit.mode == :link} class="text-xs italic dark:text-zinc-500">
          {linked_people(@credit) || "Already in the library."}
        </span>
      </form>

      <%!-- The photo and bio belong to the credit itself while there is one
            implied person behind it, which is nearly always. Putting them
            inside the pen-name fold hid them behind a control nobody would
            click to get a picture — they were, for practical purposes, not
            there at all. --%>
      <.person_curation
        :if={@credit.mode == :create and !@expanded and @credit.people != []}
        person={hd(@credit.people)}
        fallback_name={@credit.name}
        section={@section}
        index={@index}
        person_index={0}
        kind={@kind}
        sharing={@sharing}
        photos={@found[0][:photos] || []}
        bios={@found[0][:bios] || []}
        searching={@found[0][:searching] || false}
        expanded={@photos_expanded[0] || false}
      />

      <%!-- Folded away until it matters, and unfolded automatically the moment
            it does — a credit backed by somebody else, or by two people, can
            never be hiding behind a collapsed control. --%>
      <button
        :if={@credit.mode == :create and !@expanded}
        type="button"
        phx-click="toggle-people"
        phx-value-section={@section}
        phx-value-index={@index}
        class="text-xs underline dark:text-zinc-400"
      >
        {@reveal}
      </button>

      <div :if={@credit.mode == :create and @expanded} class="space-y-3">
        <.label class="text-xs">{@backing}</.label>

        <div
          :for={{person, person_index} <- Enum.with_index(@credit.people)}
          class="space-y-1 border-l border-zinc-200 pl-3 dark:border-zinc-700"
        >
          <form
            id={"credit-#{@section}-#{@index}-person-#{person_index}"}
            phx-change="person-change"
            class="flex flex-wrap items-center gap-2"
          >
            <input type="hidden" name="section" value={@section} />
            <input type="hidden" name="index" value={@index} />
            <input type="hidden" name="person" value={person_index} />

            <select
              name="person_id"
              class="rounded-sm border-zinc-300 text-sm dark:border-zinc-600 dark:bg-zinc-800"
            >
              <option value="">Create new…</option>
              <option :for={{name, id} <- @people} value={id} selected={person.person_id == id}>
                {name}
              </option>
            </select>

            <input
              :if={is_nil(person.person_id)}
              type="text"
              name="name"
              value={person.name}
              placeholder="the person's real name"
              class="min-w-0 flex-grow rounded-sm border-zinc-300 text-sm dark:border-zinc-600 dark:bg-zinc-800"
            />

            <button
              :if={length(@credit.people) > 1}
              type="button"
              phx-click="remove-person"
              phx-value-section={@section}
              phx-value-index={@index}
              phx-value-person={person_index}
            >
              <.icon name="fa-xmark" class="h-3 w-3 cursor-pointer hover:text-red-600" />
            </button>
          </form>

          <.person_curation
            person={person}
            fallback_name={@credit.name}
            section={@section}
            index={@index}
            person_index={person_index}
            kind={@kind}
            sharing={@sharing}
            photos={@found[person_index][:photos] || []}
            bios={@found[person_index][:bios] || []}
            searching={@found[person_index][:searching] || false}
            expanded={@photos_expanded[person_index] || false}
          />
        </div>

        <%!-- Narrators stay one-to-one with a Person by design; only the
              author control grows a second entry. --%>
        <button
          :if={@section == "work"}
          type="button"
          phx-click="add-person"
          phx-value-section={@section}
          phx-value-index={@index}
          class="text-xs underline dark:text-zinc-400"
        >
          Add another person
        </button>

        <p :if={length(@credit.people) > 1} class="text-xs italic dark:text-zinc-500">
          A shared pen name — {@credit.name} will be one author credited to {Enum.count(@credit.people)} people.
        </p>
      </div>
    </div>
    """
  end

  attr :person, PersonRef, required: true
  attr :fallback_name, :string, default: nil
  attr :section, :string, required: true
  attr :index, :integer, required: true
  attr :person_index, :integer, required: true
  attr :kind, :atom, required: true, doc: "which credit this row hangs off"
  attr :sharing, :map, default: %{}, doc: "PersonRef key => everywhere they appear"
  attr :photos, :list, default: []
  attr :bios, :list, default: []
  attr :searching, :boolean, default: false
  attr :expanded, :boolean, default: false, doc: "whether the whole photo set is showing"

  # Enough to see there are alternatives without the row becoming a contact
  # sheet. TMDB keeps every headshot anyone has uploaded and a working actor
  # can have dozens.
  @photo_preview 5

  @doc """
  The face and bio a new person will be created with.

  3b's promise is that the operator never leaves the inbox to finish a leaf
  entity, and a person with no face is unfinished — every credit imported
  without one was a trip to the person form afterwards.

  ## A description is a description

  This used to be a modal. Two of them, in effect: a photo grid and a bio list
  sharing one sheet, where choosing either dismissed the other, and where a
  button labelled "find a photo and bio" showed you no bios at all until it
  closed. A person's description is not a different kind of thing from a
  recording's — it wants the same editable text box with the same proposals
  underneath it, because a provider's blurb is a starting point you tweak, not
  a thing you take or leave.

  So there is no modal. The photos are chips too, circular and at the size
  they'll be seen, because **the decision is whether a face survives a circular
  crop** — which is why the alternatives matter and why the obvious portrait is
  so often the wrong one. Past the first few they fold away rather than pushing
  the rest of the credit off screen.

  ## One human is curated in one place

  A person behind two credits — an author reading their own book — is created
  once, so they are curated once: the first place they appear owns the photo
  and the bio, and the second shows what it will get. Offering to go looking
  for a picture of somebody already settled on the row above is the form
  contradicting itself about what it is going to do.
  """
  def person_curation(assigns) do
    here = {assigns.section, assigns.index, assigns.person_index}
    places = Map.get(assigns.sharing, here, [])

    assigns =
      assign(assigns,
        curated_at: List.first(places),
        mine?: places == [] or loc(List.first(places)) == here,
        shared_with: shared_with(places, assigns.kind)
      )

    ~H"""
    <div :if={is_nil(@person.person_id)} class="space-y-2" data-role="person-face">
      <div class="flex items-center gap-2">
        <.image_with_size
          :if={@person.image_url}
          id={"person-#{@section}-#{@index}-#{@person_index}-photo"}
          src={proxied_remote_image_url(@person.image_url)}
          class="h-12 w-12 flex-none rounded-full object-cover object-top"
        />

        <span
          :if={is_nil(@person.image_url)}
          class="h-12 w-12 flex-none rounded-full border border-dashed border-zinc-300 dark:border-zinc-700"
        />

        <button
          :if={@mine?}
          type="button"
          phx-click="find-person-images"
          phx-value-section={@section}
          phx-value-index={@index}
          phx-value-person={@person_index}
          disabled={blank_name?(@person, @fallback_name) or @searching}
          class="flex-none rounded-sm border border-zinc-300 px-2 py-1 text-xs disabled:opacity-50 dark:border-zinc-700"
        >
          {cond do
            @searching -> "Looking…"
            @photos != [] or @bios != [] -> "Look again"
            @person.image_url || @person.description -> "Find another photo or bio…"
            true -> "Find a photo and bio…"
          end}
        </button>

        <%!-- The same human on two credits: an author reading their own book.
              Approval creates them once, so this is where the form says so —
              on the row that would otherwise look like it was about to make a
              second person of the same name. --%>
        <p :if={@shared_with} class="min-w-0 text-xs italic dark:text-zinc-500">
          Same person as the {@shared_with} — one {@person.name || @fallback_name} will be created.
          <button
            type="button"
            phx-click="person-distinct"
            phx-value-section={@section}
            phx-value-index={@index}
            phx-value-person={@person_index}
            phx-value-distinct="true"
            class="underline"
          >
            Not the same person?
          </button>
        </p>

        <p :if={@person.distinct} class="min-w-0 text-xs italic dark:text-zinc-500">
          A different person who happens to share the name.
          <button
            type="button"
            phx-click="person-distinct"
            phx-value-section={@section}
            phx-value-index={@index}
            phx-value-person={@person_index}
            phx-value-distinct="false"
            class="underline"
          >
            Undo
          </button>
        </p>
      </div>

      <%!-- Curated where they first appear; here you see what that settled. --%>
      <p :if={!@mine?} class="text-xs italic dark:text-zinc-500">
        Photo and bio come from the {other_words(@curated_at)} credit.
      </p>

      <div :if={@mine? and @photos != []} class="flex flex-wrap items-center gap-2">
        <span class="text-xs dark:text-zinc-500">Photos:</span>

        <.proposal_chip
          :for={photo <- shown_photos(@photos, @expanded)}
          chosen={@person.image_url == photo.url}
          event="pick-person-image"
          values={
            %{
              "section" => @section,
              "index" => @index,
              "person" => @person_index,
              "provider" => photo.provider_id,
              "url" => photo.url
            }
          }
          title={photo.name}
          shape="circle"
        >
          <.image_with_size
            id={"photo-#{@section}-#{@index}-#{@person_index}-#{:erlang.phash2(photo.url)}"}
            src={proxied_remote_image_url(photo.url)}
            class="h-16 w-16 rounded-full object-cover object-top"
          />
        </.proposal_chip>

        <%!-- A dozen headshots is normal and would push the rest of the credit
              off the screen; the point is that alternatives EXIST, not that
              they're all on show. --%>
        <button
          :if={length(@photos) > photo_preview()}
          type="button"
          phx-click="toggle-photos"
          phx-value-section={@section}
          phx-value-index={@index}
          phx-value-person={@person_index}
          class="text-xs underline dark:text-zinc-400"
        >
          {if @expanded,
            do: "show fewer",
            else: "show all #{length(@photos)} photos"}
        </button>
      </div>

      <%!-- The same text box the recording's description gets, for the same
            reason: an imported blurb is a starting point. --%>
      <div :if={@mine?} class="space-y-1">
        <form
          id={"person-bio-#{@section}-#{@index}-#{@person_index}"}
          phx-change="person-bio"
          phx-submit="person-bio"
        >
          <input type="hidden" name="section" value={@section} />
          <input type="hidden" name="index" value={@index} />
          <input type="hidden" name="person" value={@person_index} />
          <textarea
            name="description"
            rows="3"
            placeholder="a short bio"
            phx-debounce="500"
            class="block w-full rounded-sm border-zinc-300 text-sm dark:border-zinc-600 dark:bg-zinc-800"
          >{@person.description}</textarea>
        </form>

        <div :if={@bios != []} class="flex flex-wrap items-center gap-2">
          <span class="text-xs dark:text-zinc-500">Proposed:</span>

          <.proposal_chip
            :for={bio <- @bios}
            chosen={@person.description == bio.description}
            event="pick-person-bio"
            values={
              %{
                "section" => @section,
                "index" => @index,
                "person" => @person_index,
                "provider" => bio.provider_id,
                "bio" => bio.id
              }
            }
            title={bio.description}
          >
            <span class="dark:text-zinc-500">{bio.provider_name}:</span>
            <span class="line-clamp-1">{truncate(bio.description)}</span>
          </.proposal_chip>
        </div>
      </div>

      <p :if={!@mine? and @person.description} class="line-clamp-2 text-xs dark:text-zinc-500">
        {@person.description}
      </p>
    </div>
    """
  end

  defp photo_preview, do: @photo_preview

  defp shown_photos(photos, true), do: photos
  defp shown_photos(photos, _collapsed), do: Enum.take(photos, @photo_preview)

  defp loc(%{section: section, index: index, person_index: person_index}),
    do: {section, index, person_index}

  defp other_words(%{kind: :author}), do: "author"
  defp other_words(%{kind: :narrator}), do: "narrator"
  defp other_words(_none), do: "other"

  # Which *other* credit the same human is behind, in the words the row needs.
  defp shared_with(places, kind) do
    places
    |> Enum.map(& &1.kind)
    |> Enum.uniq()
    |> List.delete(kind)
    |> case do
      [:author] -> "author"
      [:narrator] -> "narrator"
      _only_this_one -> nil
    end
  end

  attr :chosen, :boolean, required: true
  attr :event, :string, required: true
  attr :values, :map, default: %{}
  attr :title, :string, default: nil
  attr :shape, :string, default: "text"
  slot :inner_block, required: true

  @doc """
  One proposal, and whether it's the one in use.

  Shared by every place the form offers alternatives — a scalar's candidates, a
  person's photos, a person's bios — because they are the same interaction and
  were being hand-written each time, which is how one of them ended up with no
  way to tell which chip was chosen.
  """
  def proposal_chip(assigns) do
    ~H"""
    <button
      type="button"
      phx-click={@event}
      {chip_values(@values)}
      title={@title}
      class={[
        "max-w-full rounded-sm border text-left text-xs",
        @shape == "circle" && "rounded-full p-0.5",
        @shape != "circle" && "px-2 py-1",
        @chosen && "border-brand dark:border-brand-dark",
        !@chosen && "border-zinc-300 dark:border-zinc-700"
      ]}
    >
      {render_slot(@inner_block)}
    </button>
    """
  end

  defp chip_values(values),
    do: Map.new(values, fn {key, value} -> {"phx-value-#{key}", value} end)

  attr :link, SeriesLink, required: true
  attr :index, :integer, required: true
  attr :options, :list, required: true

  @doc """
  One series membership, with its number.

  Each series is its own decision, which is what fixes the standing complaint
  that the import forms take all series or none. The number is never
  defaulted — a series proposal with no number stays outstanding, because
  inventing "book 1" writes confident nonsense into a curated field.
  """
  def series_row(assigns) do
    ~H"""
    <div class="flex flex-wrap items-center gap-2 rounded-sm border border-zinc-300 p-3 dark:border-zinc-700">
      <.icon
        :if={SeriesLink.resolved?(@link)}
        name="fa-circle-check"
        class="text-brand h-4 w-4 flex-none dark:text-brand-dark"
      />

      <span :if={@link.mode == :link} class="font-semibold">{@link.name}</span>

      <.badge
        :if={!SeriesLink.resolved?(@link)}
        color={elem(state_words(SeriesLink.state(@link)), 1)}
        class="text-xs"
      >
        {elem(state_words(SeriesLink.state(@link)), 0)}
      </.badge>

      <form id={"series-#{@index}-number"} phx-change="set-series-number" class="flex items-center gap-1">
        <input type="hidden" name="index" value={@index} />
        <label class="text-xs dark:text-zinc-500">Book no.</label>
        <input
          type="text"
          name="number"
          value={@link.number}
          placeholder="?"
          class="w-16 rounded-sm border-zinc-300 text-sm dark:border-zinc-600 dark:bg-zinc-800"
        />
      </form>

      <form id={"series-#{@index}-link"} phx-change="link-series" class="flex items-center gap-2">
        <input type="hidden" name="index" value={@index} />
        <select
          name="series_id"
          class="rounded-sm border-zinc-300 text-sm dark:border-zinc-600 dark:bg-zinc-800"
        >
          <option value="">Create new…</option>
          <option
            :for={{name, id} <- @options}
            value={id}
            selected={@link.mode == :link and @link.series_id == id}
          >
            {name}
          </option>
        </select>

        <%!-- A provider's spelling of a series name is a proposal, not a
              decree. "The Expanse" vs "Expanse" is the operator's call. --%>
        <input
          :if={@link.mode == :create}
          type="text"
          name="name"
          value={@link.name}
          placeholder="series name"
          class="rounded-sm border-zinc-300 text-sm dark:border-zinc-600 dark:bg-zinc-800"
        />
      </form>

      <button
        :if={!@link.approved and @link.number}
        type="button"
        phx-click="approve-series"
        phx-value-index={@index}
        phx-value-approved="true"
        class="rounded-sm border border-zinc-300 px-2 py-1 text-xs dark:border-zinc-700"
      >
        Confirm
      </button>

      <button type="button" phx-click="remove-series" phx-value-index={@index} title="Not in this series">
        <.icon name="fa-xmark" class="h-4 w-4 cursor-pointer hover:text-red-600" />
      </button>
    </div>
    """
  end

  @doc """
  A decision's state as words and a colour.

  `:missing` and `:ambiguous` read differently on purpose — one needs a value
  from somewhere, the other needs a choice between values already in hand.
  Calling both "unresolved" throws that distinction away.
  """
  def state_words(:approved), do: {"settled", :brand}
  def state_words(:missing), do: {"nothing proposed it", :red}
  def state_words(:ambiguous), do: {"sources disagree", :yellow}
  def state_words(:unconfirmed), do: {"needs confirming", :yellow}
  def state_words(:stale), do: {"files changed", :red}
  def state_words(_other), do: {"needs confirming", :yellow}

  @doc """
  Where a cover value can actually be looked at.

  A provider URL goes through the admin proxy, because tracking protection
  blocks the CDNs directly. The file's own art isn't a URL at all — the value
  is the audio file to extract from — so it gets an endpoint that extracts it
  on demand rather than a line of text saying it exists.
  """
  def preview_src(nil, _embedded), do: nil
  def preview_src("", _embedded), do: nil
  def preview_src("http" <> _rest = url, _embedded), do: proxied_remote_image_url(url)
  def preview_src(_local_path, embedded), do: embedded

  @doc "Whose proposal this is, in words rather than an id."
  def source_words(nil), do: "nothing"
  def source_words("manual"), do: "you"
  def source_words("tags"), do: "the file's tags"
  def source_words("release_name"), do: "the release name"
  def source_words("embedded"), do: "the file's embedded art"
  def source_words("default"), do: "the default"
  def source_words("date"), do: "the date itself"
  def source_words("local"), do: "the library"
  def source_words("provider:" <> id), do: id
  def source_words(other), do: other

  defp blank_name?(person, fallback) do
    (person.name || fallback || "") |> String.trim() == ""
  end

  defp linked_people(%Credit{candidates: candidates, identity_id: id}) do
    case Enum.find(candidates, &(&1.identity_id == id)) do
      %{people: people} when is_binary(people) -> "Already in the library — #{people}."
      _none -> nil
    end
  end

  defp truncate(nil), do: "—"

  defp truncate(value) when is_binary(value) do
    if String.length(value) > 60, do: String.slice(value, 0, 60) <> "…", else: value
  end

  defp truncate(other), do: to_string(other)
end
