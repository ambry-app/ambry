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
  alias Ambry.Inbox.Draft.PersonDecision
  alias Ambry.Inbox.Draft.SeriesLink
  alias Ambry.Inbox.Draft.SourceRef
  alias AmbryWeb.Components.EntityResolver

  @doc """
  The app-standard input styling, for the controls the import form builds by
  hand.

  The admin forms get this through `<.input>`; a bare `<input>` or `<select>`
  rendered here has to carry it itself or it falls back to the browser's blue
  focus ring, which is exactly what happened.
  """
  def input_classes(extra \\ nil) do
    [
      "rounded-sm text-sm focus:outline-none focus:ring-4",
      "bg-white text-zinc-900 placeholder:text-zinc-500 dark:bg-zinc-800 dark:text-zinc-300",
      "border-zinc-300 focus:border-zinc-400 focus:ring-zinc-800/5",
      "dark:border-zinc-600 dark:focus:border-zinc-400 dark:focus:ring-zinc-200/5",
      extra
    ]
  end

  attr :outcomes, :list, required: true
  attr :level, :string, default: nil
  attr :retrying, :any, default: nil

  attr :retryable, :boolean,
    default: true,
    doc: "person-level outcomes have no per-provider retry yet"

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
      <span class="text-[10px] font-semibold uppercase tracking-wider text-zinc-500 dark:text-zinc-400">
        Asked
      </span>

      <%!-- A count is information, not an option — filled and quiet, so it
            can't be mistaken for the clickable proposal chips nearby. --%>
      <span
        :for={outcome <- @outcomes}
        :if={outcome["status"] != "failed"}
        class="rounded-sm bg-zinc-100 px-2 py-0.5 text-xs tabular-nums text-zinc-600 dark:bg-zinc-800 dark:text-zinc-300"
      >
        {outcome["name"]}: {outcome["count"]}
      </span>

      <%!-- A provider that was rate-limited during matching used to cost this
            item its records until somebody re-ran the whole match. The chip is
            the retry. --%>
      <button
        :for={outcome <- @outcomes}
        :if={outcome["status"] == "failed" and @retryable}
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

      <span
        :for={outcome <- @outcomes}
        :if={outcome["status"] == "failed" and not @retryable}
        title={outcome["reason"]}
        class="rounded-sm border border-red-500 px-2 py-0.5 text-xs text-red-600"
      >
        {outcome["name"]}: couldn't be reached
      </span>
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
        <span class="text-zinc-500 dark:text-zinc-400">{key}:</span>
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
  attr :level, :string, default: nil
  attr :event, :string, default: "toggle-source"
  attr :person_key, :string, default: nil, doc: "set for person records — routes the toggle"
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
        phx-click={@event}
        phx-value-level={@level}
        phx-value-key={@person_key}
        phx-value-source={@record["source"]}
        phx-value-id={@record["id"]}
        class="mt-1 h-4 w-4 flex-none rounded-sm"
      />
      <div class="min-w-0 flex-grow">
        <p class="truncate text-sm font-medium">{candidate_title(@record)}</p>
        <p class="truncate text-xs dark:text-zinc-500">{candidate_facts(@record)}</p>
      </div>
      <span :if={@working} class="flex-none pt-0.5 text-xs dark:text-zinc-400">
        fetching…
      </span>
      <%!-- The meter makes the ranking visible before the number is read —
            eight cards with bare percentages all carried identical visual
            weight whether they were a 100% match or a 6% study guide. --%>
      <span :if={!@working && @record["score"]} class="flex flex-none flex-col items-end gap-1 pt-0.5">
        <span class="text-xs tabular-nums text-zinc-500 dark:text-zinc-400">
          {round(@record["score"] * 100)}%
        </span>
        <span class="h-1 w-16 overflow-hidden rounded-full bg-zinc-200 dark:bg-zinc-800">
          <span
            class={["block h-full rounded-full", meter_color(@record["score"])]}
            style={"width: #{round(@record["score"] * 100)}%"}
          />
        </span>
      </span>
    </label>
    """
  end

  # High reads as the accent, the murky middle as a warning, and junk as
  # neutral — the same bands the matcher's own trust thresholds use.
  defp meter_color(score) when score >= 0.75, do: "bg-brand dark:bg-brand-dark"
  defp meter_color(score) when score >= 0.4, do: "bg-amber-500 dark:bg-amber-400"
  defp meter_color(_score), do: "bg-zinc-400 dark:bg-zinc-600"

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

  attr :at, :string, required: true, doc: "where this renders — DOM ids key on place, not person"
  attr :person_key, :string, required: true
  attr :name, :string, default: nil
  attr :running, :boolean, default: false

  @doc """
  The person level's search-again form — the work-level pattern with a name
  where the work has title and author.
  """
  def person_research_form(assigns) do
    ~H"""
    <form
      id={"research-person-#{@at}"}
      phx-submit="research-person"
      class="flex flex-wrap items-end gap-2"
    >
      <input type="hidden" name="key" value={@person_key} />

      <label class="text-xs dark:text-zinc-500">
        name <input type="text" name="name" value={@name} class={input_classes("mt-1 block")} />
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
          class={input_classes("mt-1 block")}
        />
      </label>

      <label class="text-xs dark:text-zinc-500">
        author
        <input
          type="text"
          name="author"
          value={@fields["author"]}
          class={input_classes("mt-1 block")}
        />
      </label>

      <label :if={@level == "recording"} class="text-xs dark:text-zinc-500">
        narrator
        <input
          type="text"
          name="narrator"
          value={@fields["narrator"]}
          class={input_classes("mt-1 block")}
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
    [
      candidate["title"] || candidate["name"],
      candidate["authors"] && Enum.join(candidate["authors"], ", ")
    ]
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
      # person records: whether it brings a face, and the words that tell a
      # namesake apart
      candidate["images"] not in [nil, []] && "has a photo",
      is_binary(candidate["name"]) && bio_snippet(candidate["description"]),
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

  defp bio?(description), do: is_binary(description) and String.trim(description) != ""

  # The first words of the bio are what tells a namesake apart — "an English
  # professional footballer" is a sentence the operator must get to read
  # before ticking.
  defp bio_snippet(description) do
    if bio?(description), do: String.slice(description, 0, 90)
  end

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
    <%!-- One slot order for every field — label row, control, options, hint —
          with an 8px beat inside the cluster. The 28px to the *next* field
          comes from the section, so the ratio between "mine" and "not mine"
          stays legible (see the admin design review, rhythm rules). --%>
    <div class="space-y-2">
      <div class="flex items-center gap-2">
        <.label>{@label}</.label>

        <.badge
          :if={!@field.approved}
          color={elem(state_words(Field.state(@field)), 1)}
          class="text-xs"
        >
          {elem(state_words(Field.state(@field)), 0)}
        </.badge>

        <span :if={@field.approved && @field.source} class="text-xs text-zinc-500 dark:text-zinc-400">
          from {source_words(@field.source)}
        </span>

        <span :if={@field.approved && is_nil(@field.source)} class="text-xs text-zinc-500 dark:text-zinc-400">
          left empty on purpose
        </span>
      </div>

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
              :if={@type not in ["select", "textarea"]}
              field={decision[:value]}
              type={@type}
              placeholder={@placeholder}
            />
            <%!-- A description is markdown, and markdown in a plain box is
                  written blind — the same textarea/preview pair the person
                  form has had all along. --%>
            <div :if={@type == "textarea"} class="grid grid-cols-1 gap-2 sm:grid-cols-2">
              <.input
                id={"#{@section}-#{@name}-input"}
                field={decision[:value]}
                type="textarea"
                placeholder={@placeholder}
                phx-hook="maintain-attrs"
                data-attrs="style"
              />
              <div class="relative">
                <div
                  id={"#{@section}-#{@name}-preview"}
                  phx-hook="scroll-match"
                  data-target={"#{@section}-#{@name}-input"}
                  class="absolute inset-0 hidden overflow-auto rounded-sm border border-zinc-300 dark:border-zinc-800 sm:block"
                >
                  <.markdown content={@field.value || ""} class="p-2" />
                </div>
              </div>
            </div>
          </.inputs_for>
        </div>
      </div>

      <%!-- Options hang visibly *inside* their field: indented to the
            control's inner padding, so a wrapped chip row still reads as
            belonging to the input above it and not to the next label. --%>
      <div :if={@field.candidates != []} class="flex flex-wrap items-center gap-2 pl-3">
        <span class="text-[10px] font-semibold uppercase tracking-wider text-zinc-500 dark:text-zinc-400">
          Proposed
        </span>

        <.proposal_chip
          :for={candidate <- @field.candidates}
          chosen={Field.chose?(@field, candidate)}
          event="choose-field"
          values={%{section: @section, field: @name, key: candidate.key}}
        >
          <span class={[
            "text-[10px] flex-none rounded-sm px-1 uppercase tracking-wide",
            Field.chose?(@field, candidate) && "bg-brand/90 text-zinc-900 dark:bg-brand-dark",
            !Field.chose?(@field, candidate) && "bg-zinc-100 text-zinc-600 dark:bg-zinc-800 dark:text-zinc-400"
          ]}>
            {candidate.label || source_words(candidate.source)}
          </span>
          <span :if={!@preview}>{truncate(candidate.value)}</span>

          <%!-- Choosing between two covers by URL is choosing blind. --%>
          <.image_with_size
            :if={@preview && preview_src(candidate.value, @embedded_src)}
            id={"#{@section}-#{@name}-#{candidate.key}"}
            src={preview_src(candidate.value, @embedded_src)}
            class="mt-1 h-20 w-20 rounded-sm object-cover"
          />
        </.proposal_chip>

        <%!-- Choosing "none" is an approval, not an omission. It's what makes
              "every piece is settled" reachable on a record with optional
              fields nobody filled in. --%>
        <.proposal_chip
          :if={!@field.required}
          chosen={@field.approved && is_nil(@field.source)}
          event="waive-field"
          values={%{section: @section, field: @name}}
        >
          None
        </.proposal_chip>
      </div>

      <p :if={@hint} class="pl-3 text-xs text-zinc-500 dark:text-zinc-400">{@hint}</p>
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

  attr :identity_backing, :map,
    default: %{},
    doc: "identity id => the backing people's names, where they add something"

  attr :person_records, :map,
    default: %{},
    doc: "person key => the provider records of people by that name"

  attr :person_outcomes, :map,
    default: %{},
    doc: "person key => what each person provider said when asked"

  attr :persons, :list, required: true, doc: "the PersonDecisions this credit references"
  attr :appearances, :map, default: %{}, doc: "person key => every credit referencing them"
  attr :searching_person, :string, default: nil, doc: "the person being looked up again"
  attr :photos_expanded, :map, default: %{}, doc: "person key => whether all photos show"

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

        <.live_component
          module={EntityResolver}
          id={"credit-#{@section}-#{@index}-resolver"}
          name="identity_id"
          text_name="name"
          options={@identities}
          value={if @credit.mode == :link, do: @credit.identity_id}
          text={@credit.name || ""}
          placeholder="name"
          class={input_classes("w-full")}
        />

        <%!-- The prefix segment already says "Existing"; this only speaks
              when the linked identity is backed by other humans — a pen
              name's real names are worth a line, "already in the library"
              twice is not. --%>
        <span
          :if={@credit.mode == :link && @identity_backing[@credit.identity_id]}
          class="text-xs italic dark:text-zinc-500"
          data-role="identity-backing"
        >
          {@identity_backing[@credit.identity_id]}
        </span>
      </form>

      <%!-- The photo and bio belong to the credit itself while there is one
            implied person behind it, which is nearly always. Putting them
            inside the pen-name fold hid them behind a control nobody would
            click to get a picture — they were, for practical purposes, not
            there at all. --%>
      <.person_curation
        :if={@credit.mode == :create and !@expanded and @persons != []}
        person={hd(@persons)}
        section={@section}
        index={@index}
        person_index={0}
        kind={@kind}
        appears={@appearances[hd(@persons).key] || []}
        searching={@searching_person == hd(@persons).key}
        expanded={@photos_expanded[hd(@persons).key] || false}
        records={@person_records[hd(@persons).key] || []}
        outcomes={@person_outcomes[hd(@persons).key] || []}
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
          :for={{person, person_index} <- Enum.with_index(@persons)}
          class="space-y-1 border-l border-zinc-200 pl-3 dark:border-zinc-700"
        >
          <form
            id={"credit-#{@section}-#{@index}-person-#{person_index}"}
            phx-change="person-change"
            class="flex flex-wrap items-center gap-2"
          >
            <input type="hidden" name="key" value={person.key} />

            <.live_component
              module={EntityResolver}
              id={"credit-#{@section}-#{@index}-person-#{person_index}-resolver"}
              name="person_id"
              text_name="name"
              options={@people}
              value={if person.mode == :link, do: person.person_id}
              text={Field.value(person.name) || ""}
              placeholder="the person's real name"
              class={input_classes("w-full")}
            />

            <button
              :if={length(@persons) > 1}
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
            section={@section}
            index={@index}
            person_index={person_index}
            kind={@kind}
            appears={@appearances[person.key] || []}
            searching={@searching_person == person.key}
            expanded={@photos_expanded[person.key] || false}
            records={@person_records[person.key] || []}
            outcomes={@person_outcomes[person.key] || []}
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

        <p :if={length(@persons) > 1} class="text-xs italic dark:text-zinc-500">
          A shared pen name — {@credit.name} will be one author credited to {length(@persons)} people.
        </p>
      </div>
    </div>
    """
  end

  attr :person, PersonDecision, required: true
  attr :section, :string, required: true
  attr :index, :integer, required: true
  attr :person_index, :integer, required: true
  attr :kind, :atom, required: true, doc: "which credit this row hangs off"
  attr :appears, :list, default: [], doc: "every credit referencing this person"
  attr :searching, :boolean, default: false
  attr :expanded, :boolean, default: false, doc: "whether the whole photo set is showing"
  attr :records, :list, default: [], doc: "the provider records of people by this name"
  attr :outcomes, :list, default: [], doc: "what each person provider said when asked"

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

  ## One human is one record

  A person behind two credits — an author reading their own book — is created
  once and is now *stored* once: both credits reference the same
  `PersonDecision` by key. The row therefore shows the same photo in both
  places because it is the same photo, not because two copies are being kept
  in step. Editing either edits the person.

  ## The photos are already here

  Matching asks every person-level provider about every credited human, so the
  candidates arrive with the item and the grid renders with nothing to click
  first. "Look again" is the escape hatch for a name that has *changed* since
  — a rename, a pen name revealed — where nobody has searched for who this now
  is.
  """
  def person_curation(assigns) do
    assigns =
      assign(assigns,
        # One person can be rendered in two places — an author who reads their
        # own book — so DOM ids are keyed by WHERE this is, not by who it is.
        # The person key travels in the form's hidden field, where it belongs:
        # the edit targets the human, the id targets the element.
        at: "#{assigns.section}-#{assigns.index}-#{assigns.person_index}",
        image: Field.value(assigns.person.image),
        description: Field.value(assigns.person.description),
        photos: assigns.person.image.candidates,
        bios: assigns.person.description.candidates,
        shared_with: shared_with(assigns.appears, assigns.kind)
      )

    ~H"""
    <div :if={@person.mode == :create} class="space-y-2" data-role="person-face">
      <div class="flex items-center gap-2">
        <.image_with_size
          :if={@image}
          id={"person-#{@at}-photo"}
          src={proxied_remote_image_url(@image)}
          class="h-12 w-12 flex-none rounded-full object-cover object-top"
        />

        <span
          :if={is_nil(@image)}
          class="h-12 w-12 flex-none rounded-full border border-dashed border-zinc-300 dark:border-zinc-700"
        />

        <%!-- The same human on two credits: an author reading their own book.
              Approval creates them once, so this is where the form says so —
              on the row that would otherwise look like it was about to make a
              second person of the same name. --%>
        <p :if={@shared_with} class="min-w-0 text-xs italic dark:text-zinc-500">
          Same person as the {@shared_with} — one {Field.value(@person.name)} will be created.
          <button
            type="button"
            phx-click="split-person"
            phx-value-section={@section}
            phx-value-index={@index}
            phx-value-person={@person_index}
            class="underline"
          >
            Not the same person?
          </button>
        </p>
      </div>

      <%!-- Nothing found is a normal outcome, not a failure — plenty of
            narrators are in no database at all — but it should say so rather
            than looking like an empty grid nobody filled in. --%>
      <p :if={@person.doubt == :low_confidence} class="text-xs italic dark:text-zinc-500">
        {@person.doubt_detail}
      </p>

      <%!-- The same evidence rule as the work and recording levels, one
            paradigm across all three: tick every record of THIS human, and
            the photo and bio pools draw from the ticked set. The exact-name
            gate decides the initial ticks; a differently-spelled record of
            the right person is exactly what the checkbox is for. --%>
      <p :if={@records != []} class="text-xs dark:text-zinc-400">
        Tick every record of <em>this person</em> — the photos and bios on offer come from the
        ticked ones. Databases know several people by many names, so check before ticking.
      </p>

      <.record_row
        :for={record <- @records}
        record={record}
        event="toggle-person-source"
        person_key={@person.key}
        used={Enum.any?(@person.sources, &SourceRef.points_at?(&1, record))}
      />

      <.provider_outcomes_row outcomes={@outcomes} retryable={false} />

      <details>
        <summary class="cursor-pointer text-xs dark:text-zinc-400">
          Not the right person? Search again
        </summary>
        <div class="pt-2">
          <.person_research_form
            at={@at}
            person_key={@person.key}
            name={Field.value(@person.name)}
            running={@searching}
          />
        </div>
      </details>

      <div :if={@photos != []} class="flex flex-wrap items-center gap-2">
        <span class="text-xs dark:text-zinc-500">Photos:</span>

        <.proposal_chip
          :for={photo <- shown_photos(@photos, @expanded)}
          chosen={Field.chose?(@person.image, photo)}
          event="pick-person-image"
          values={%{"key" => @person.key, "candidate" => photo.key}}
          title={photo.label}
          shape="circle"
        >
          <.image_with_size
            id={"photo-#{@at}-#{:erlang.phash2(photo.value)}"}
            src={proxied_remote_image_url(photo.value)}
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
          phx-value-key={@person.key}
          class="text-xs underline dark:text-zinc-400"
        >
          {if @expanded, do: "show fewer", else: "show all #{length(@photos)} photos"}
        </button>

        <button
          :if={@image}
          type="button"
          phx-click="waive-person-field"
          phx-value-key={@person.key}
          phx-value-field="image"
          class="text-xs underline dark:text-zinc-400"
        >
          no photo
        </button>
      </div>

      <%!-- The same text box the recording's description gets, for the same
            reason: an imported blurb is a starting point. --%>
      <div class="space-y-1">
        <div class="grid grid-cols-1 gap-2 sm:grid-cols-2">
          <form id={"person-bio-#{@at}"} phx-change="person-bio" phx-submit="person-bio">
            <input type="hidden" name="key" value={@person.key} />
            <textarea
              id={"person-bio-#{@at}-input"}
              name="description"
              rows="3"
              placeholder="a short bio"
              phx-debounce="500"
              phx-hook="maintain-attrs"
              data-attrs="style"
              class={input_classes("block w-full")}
            >{@description}</textarea>
          </form>
          <div class="relative">
            <div
              id={"person-bio-#{@at}-preview"}
              phx-hook="scroll-match"
              data-target={"person-bio-#{@at}-input"}
              class="absolute inset-0 hidden overflow-auto rounded-sm border border-zinc-300 dark:border-zinc-800 sm:block"
            >
              <.markdown content={@description || ""} class="p-2" />
            </div>
          </div>
        </div>

        <div :if={@bios != []} class="flex flex-wrap items-center gap-2">
          <span class="text-xs dark:text-zinc-500">Proposed:</span>

          <.proposal_chip
            :for={bio <- @bios}
            chosen={Field.chose?(@person.description, bio)}
            event="pick-person-bio"
            values={%{"key" => @person.key, "candidate" => bio.key}}
            title={bio.value}
          >
            <span class="dark:text-zinc-500">{bio.label}:</span>
            <span class="line-clamp-1">{truncate(bio.value)}</span>
          </.proposal_chip>
        </div>
      </div>
    </div>
    """
  end

  defp photo_preview, do: @photo_preview

  defp shown_photos(photos, true), do: photos
  defp shown_photos(photos, _collapsed), do: Enum.take(photos, @photo_preview)

  # Which *other* credit the same human is behind, in the words the row needs.
  defp shared_with(appears, kind) do
    appears
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
        @shape != "circle" && "inline-flex items-center gap-1.5 px-2 py-1",
        @chosen && "border-brand bg-brand/10 dark:border-brand-dark dark:bg-brand-dark/10",
        !@chosen && "border-zinc-300 hover:border-zinc-400 dark:border-zinc-700 dark:hover:border-zinc-500"
      ]}
    >
      <%!-- The chosen chip is the single most important state on the form, and
            a 1px border-hue change was nearly invisible — so it says so three
            ways: border, tint, and a check. --%>
      <.icon
        :if={@chosen && @shape != "circle"}
        name="fa-check"
        class="h-3 w-3 flex-none text-lime-700 dark:text-brand-dark"
      />
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
          class={input_classes("w-16")}
        />
      </form>

      <form
        id={"series-#{@index}-link"}
        phx-change="link-series"
        class="min-w-48 flex flex-grow items-center gap-2"
      >
        <input type="hidden" name="index" value={@index} />
        <%!-- A provider's spelling of a series name is a proposal, not a
              decree. "The Expanse" vs "Expanse" is the operator's call. --%>
        <.live_component
          module={EntityResolver}
          id={"series-#{@index}-resolver"}
          name="series_id"
          text_name="name"
          options={@options}
          value={if @link.mode == :link, do: @link.series_id}
          text={@link.name || ""}
          placeholder="series name"
          class={input_classes("w-full")}
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

  defp truncate(nil), do: "—"

  defp truncate(value) when is_binary(value) do
    if String.length(value) > 60, do: String.slice(value, 0, 60) <> "…", else: value
  end

  defp truncate(other), do: to_string(other)
end
