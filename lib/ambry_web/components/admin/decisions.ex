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

  attr :label, :string, required: true
  attr :section, :string, required: true
  attr :name, :atom, required: true
  attr :form, :any, required: true, doc: "the enclosing work/recording form"
  attr :field, Field, required: true, doc: "the staged decision itself"
  attr :type, :string, default: "text"
  attr :options, :list, default: nil
  attr :placeholder, :string, default: nil

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
      </div>

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
  attr :verb, :string, required: true

  @doc """
  One credit, resolved to an identity.

  The vocabulary is doing the teaching: **Credited as** is the name on the
  book, **Written by** / **Performed by** are the humans behind it. Two or more
  people is a shared pen name — the whole of the composite-author case,
  expressed as a longer list rather than a separate mode, which is what stops
  the case space exploding.

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
          <span class="truncate font-semibold">{@credit.name}</span>

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
            Looks right
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

      <div class="grid grid-cols-1 gap-2 sm:grid-cols-2">
        <div>
          <.label class="text-xs">Credited as</.label>
          <form id={"credit-#{@section}-#{@index}-identity"} phx-change="link-credit">
            <input type="hidden" name="section" value={@section} />
            <input type="hidden" name="index" value={@index} />
            <select
              name="identity_id"
              class="mt-1 w-full rounded-sm border-zinc-300 text-sm dark:border-zinc-600 dark:bg-zinc-800"
            >
              <option value="">Create "{@credit.name}"</option>
              <option
                :for={{name, id} <- @identities}
                value={id}
                selected={@credit.mode == :link and @credit.identity_id == id}
              >
                {name}
              </option>
            </select>
          </form>
        </div>

        <div :if={@credit.mode == :create}>
          <.label class="text-xs">{@verb}</.label>

          <div class="mt-1 space-y-1">
            <form
              :for={{person, person_index} <- Enum.with_index(@credit.people)}
              id={"credit-#{@section}-#{@index}-person-#{person_index}"}
              phx-change="set-person"
              class="flex items-center gap-1"
            >
              <input type="hidden" name="section" value={@section} />
              <input type="hidden" name="index" value={@index} />
              <input type="hidden" name="person" value={person_index} />

              <select
                name="person_id"
                class="w-full rounded-sm border-zinc-300 text-sm dark:border-zinc-600 dark:bg-zinc-800"
              >
                <option value="">New person: {person.name || @credit.name}</option>
                <option :for={{name, id} <- @people} value={id} selected={person.person_id == id}>
                  {name}
                </option>
              </select>

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

        <p :if={@credit.mode == :link} class="self-end text-xs italic dark:text-zinc-500">
          {linked_people(@credit) || "Already in the library."}
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

      <span class="font-semibold">{@link.name}</span>

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

      <form id={"series-#{@index}-link"} phx-change="link-series">
        <input type="hidden" name="index" value={@index} />
        <select
          name="series_id"
          class="rounded-sm border-zinc-300 text-sm dark:border-zinc-600 dark:bg-zinc-800"
        >
          <option value="">Create "{@link.name}"</option>
          <option
            :for={{name, id} <- @options}
            value={id}
            selected={@link.mode == :link and @link.series_id == id}
          >
            {name}
          </option>
        </select>
      </form>

      <button
        :if={!@link.approved and @link.number}
        type="button"
        phx-click="approve-series"
        phx-value-index={@index}
        phx-value-approved="true"
        class="rounded-sm border border-zinc-300 px-2 py-1 text-xs dark:border-zinc-700"
      >
        Looks right
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
  def state_words(:missing), do: {"needs a value", :red}
  def state_words(:ambiguous), do: {"sources disagree", :yellow}
  def state_words(:unconfirmed), do: {"needs a look", :yellow}
  def state_words(:stale), do: {"files changed", :red}
  def state_words(_other), do: {"needs a look", :yellow}

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
