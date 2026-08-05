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
  alias Ambry.Inbox.Draft.SeriesLink

  attr :outcomes, :list, required: true

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
        class={[
          "rounded-sm border px-2 py-0.5 text-xs",
          outcome["status"] == "failed" && "border-red-500 text-red-600",
          outcome["status"] != "failed" && "border-zinc-300 dark:border-zinc-700"
        ]}
        title={outcome["reason"]}
      >
        {outcome["name"]}: {if outcome["status"] == "failed",
          do: "couldn't be reached",
          else: outcome["count"]}
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

  attr :candidate, :map, required: true
  attr :selected, :boolean, required: true
  attr :event, :string, required: true
  attr :subtitle, :string, default: nil

  @doc """
  One candidate for an identity decision — a book, or a catalogued recording.

  A list where every row wore a checkmark was the clearest symptom of the
  decision model not reaching the UI: the item is a recording of exactly ONE
  work, so exactly one row can be the answer and the rest are what it isn't.
  """
  def candidate_option(assigns) do
    ~H"""
    <div
      class={[
        "flex cursor-pointer items-start gap-3 rounded-sm border p-2",
        @selected && "border-brand bg-brand/5 dark:border-brand-dark dark:bg-brand-dark/10",
        !@selected && "border-zinc-300 hover:border-zinc-400 dark:border-zinc-700 dark:hover:border-zinc-500"
      ]}
      phx-click={@event}
      phx-value-source={@candidate["source"]}
      phx-value-id={@candidate["id"]}
      data-role="candidate"
      data-selected={@selected && "true"}
    >
      <.icon
        name={if @selected, do: "fa-circle-check", else: "fa-circle"}
        class={[
          "mt-0.5 h-4 w-4 flex-none",
          @selected && "text-brand dark:text-brand-dark",
          !@selected && "text-zinc-300 dark:text-zinc-700"
        ]}
      />
      <div class="min-w-0 flex-grow">
        <p class="truncate text-sm">{candidate_title(@candidate)}</p>
        <p class="truncate text-xs dark:text-zinc-500">{@subtitle || candidate_facts(@candidate)}</p>
      </div>
      <span :if={@candidate["score"]} class="flex-none pt-0.5 text-xs dark:text-zinc-600">
        {round(@candidate["score"] * 100)}%
      </span>
    </div>
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
              way to catch a provider that returned the wrong edition's art,
              and it costs one tag. --%>
        <img
          :if={@preview && @field.value not in [nil, ""] && web_image?(@field.value)}
          src={@field.value}
          alt=""
          class="h-24 w-24 flex-none rounded-sm object-cover"
        />
        <p
          :if={@preview && @field.value not in [nil, ""] && !web_image?(@field.value)}
          class="flex h-24 w-24 flex-none items-center justify-center rounded-sm border border-zinc-300 text-center text-xs dark:border-zinc-700 dark:text-zinc-500"
        >
          embedded in the file
        </p>

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
          phx-value-source={candidate.source}
          class={[
            "rounded-sm border px-2 py-1 text-left text-xs",
            @field.source == candidate.source && "border-brand dark:border-brand-dark",
            @field.source != candidate.source && "border-zinc-300 dark:border-zinc-700"
          ]}
        >
          <span class="dark:text-zinc-500">{candidate.label || source_words(candidate.source)}:</span>
          <span>{truncate(candidate.value)}</span>
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

      <div :if={@credit.mode == :create and @expanded} class="space-y-1">
        <.label class="text-xs">{@backing}</.label>

        <form
          :for={{person, person_index} <- Enum.with_index(@credit.people)}
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

  @doc "Whether a cover value is something a browser can render inline."
  def web_image?("http://" <> _rest), do: true
  def web_image?("https://" <> _rest), do: true
  def web_image?(_other), do: false

  @doc "Whose proposal this is, in words rather than an id."
  def source_words(nil), do: "nothing"
  def source_words("manual"), do: "you"
  def source_words("tags"), do: "the file's tags"
  def source_words("release_name"), do: "the release name"
  def source_words("embedded"), do: "the file's embedded art"
  def source_words("default"), do: "the default"
  def source_words("local"), do: "the library"
  def source_words("provider:" <> id), do: id
  def source_words(other), do: other

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
