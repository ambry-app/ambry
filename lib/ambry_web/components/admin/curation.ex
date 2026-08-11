defmodule AmbryWeb.Admin.Curation do
  @moduledoc """
  The edit forms' curation surface: an evidence panel, and fields that grow
  "Proposed" chips from it.

  This is the import form's vocabulary — `record_row`, `provider_outcomes_row`,
  `research_form`, `proposal_chip` — composed for a record that already
  exists. The anatomy differences are the context's, not new costumes: an
  edit form's fields aren't *waiting* on anyone (no state rails, no
  amber/settled machinery — the record is real and every field already has
  its value), and its evidence panel is session state rather than a stored
  draft, so the panel starts as just a search and remembers nothing after
  the page is left. What an accepted proposal leaves behind is the field's
  provenance entry, which is the part that lives forever — so provenance is
  worn inline in each field's header, where the import form says
  "from rreading_glasses".
  """

  use Phoenix.Component

  import AmbryWeb.Admin.Components, only: [disclosure: 1, microlabel: 1]

  import AmbryWeb.Admin.Decisions,
    only: [
      provider_outcomes_row: 1,
      proposal_chip: 1,
      record_row: 1,
      research_form: 1,
      source_words: 1
    ]

  import AmbryWeb.CoreComponents

  alias Ambry.Provenance
  alias AmbryWeb.Admin.Evidence
  alias Phoenix.HTML.FormField

  attr :evidence, Evidence, required: true
  attr :level, :string, required: true, doc: ~s("work" or "recording" — routes the fan-out)
  attr :title, :string, required: true
  attr :hint, :string, default: nil
  attr :retrying, :any, default: nil

  @doc """
  The evidence panel: one search, fanned out to every capable provider, its
  results tickable records.

  Sits **outside** the record's own `<form>` (the search is a form of its
  own), above it — evidence first, then the decisions it feeds, the order
  the import form established. It starts **folded**: an edit form is
  visited for reasons that mostly aren't curation, and a paragraph of
  tick-these-records instructions above a form with no records was noise.
  The hint appears with the records it explains.
  """
  def evidence_panel(assigns) do
    ~H"""
    <%!-- `open` is pinned server-side once a search runs: LiveView patches
        strip a client-toggled open attribute (any results arriving would
        slam the panel shut), and a panel with records in it should stay
        open anyway. --%>
    <.disclosure
      class="pl-3 text-sm font-semibold text-zinc-200"
      container_class="space-y-2"
      data-role="evidence-panel"
      open={@evidence.running? or @evidence.searched?}
    >
      <:summary_slot>
        {@title}
        <span :if={@evidence.searched?} class="font-normal text-zinc-400">
          · {length(@evidence.records)} records, {MapSet.size(@evidence.used)} ticked
        </span>
      </:summary_slot>

      <p :if={@hint && @evidence.records != []} class="max-w-prose pt-1 pl-3 text-sm text-zinc-400">
        {@hint}
      </p>

      <div class="mt-2 space-y-2 rounded-lg bg-zinc-900 p-4">
        <.record_row
          :for={record <- @evidence.records}
          record={record}
          used={Evidence.used?(@evidence, record)}
          level={@level}
          event="toggle-evidence"
          note={Evidence.note(@evidence, record)}
        />

        <p
          :if={@evidence.searched? and not @evidence.running? and @evidence.records == []}
          class="pl-3 text-sm text-zinc-400"
        >
          Nothing came back — try different words.
        </p>

        <.provider_outcomes_row
          outcomes={@evidence.outcomes}
          level={@level}
          retrying={@retrying}
          retryable={@level != "person"}
        />

        <.research_form
          :if={@level != "person"}
          level={@level}
          fields={@evidence.fields}
          running={@evidence.running?}
          label={(@evidence.searched? && "Search again") || "Search"}
        />

        <%!-- A person is searched by name — the research form's
            title/author/narrator fields are the books' vocabulary. --%>
        <form
          :if={@level == "person"}
          id="research-person"
          phx-submit="research"
          class="flex flex-wrap items-end gap-2"
        >
          <label class="text-xs text-zinc-400">
            <span class="block pl-3">name</span>
            <input
              type="text"
              name="name"
              value={@evidence.fields["name"]}
              class={input_classes("mt-1 block")}
            />
          </label>

          <.button color={:zinc} type="submit" disabled={@evidence.running?}>
            {cond do
              @evidence.running? -> "Searching…"
              @evidence.searched? -> "Search again"
              true -> "Search"
            end}
          </.button>
        </form>
      </div>
    </.disclosure>
    """
  end

  attr :field, FormField, required: true
  attr :label, :string, required: true
  attr :type, :string, default: "text"
  attr :options, :list, default: nil
  attr :class, :any, default: nil, doc: "sizes the control to its content (§7)"
  attr :record, :any, default: nil, doc: "the persisted struct provenance is read from"
  attr :hints, :map, default: %{}, doc: "pending provenance hints, field name → hint"
  attr :proposals, :list, default: [], doc: "what ticked evidence proposes, `:chosen` included"
  attr :rest, :global

  @doc """
  One provider-fillable scalar: label, where its value came from, the
  control, and what the ticked evidence proposes.

  The header is the import form's "from …" idiom pointed at `Provenance`:
  the recorded source (muted), or the amber pending source when a proposal
  was accepted this session and saving will record it.
  """
  def curated_input(assigns) do
    ~H"""
    <div class="space-y-2">
      <div class="flex items-baseline gap-2 pl-3">
        <.label for={@field.id}>{@label}</.label>
        <.provenance_flag record={@record} field={@field.field} hints={@hints} />
      </div>

      <.input field={@field} type={@type} options={@options} class={@class} {@rest} />

      <.proposal_row
        id={"proposals-#{@field.id}"}
        field={to_string(@field.field)}
        proposals={@proposals}
      />
    </div>
    """
  end

  attr :date_field, FormField, required: true
  attr :format_field, FormField, required: true
  attr :label, :string, required: true
  attr :record, :any, default: nil
  attr :hints, :map, default: %{}
  attr :proposals, :list, default: []

  @doc """
  A curated composite date: label, provenance, one date+precision control,
  and combined chips — a chip proposes both halves and accepting settles
  both, so "the date from Hardcover but the precision from rreading-glasses"
  stopped being a choice anyone is offered.
  """
  def curated_date(assigns) do
    ~H"""
    <div class="space-y-2">
      <div class="flex items-baseline gap-2 pl-3">
        <.label for={@date_field.id}>{@label}</.label>
        <.provenance_flag record={@record} field={@date_field.field} hints={@hints} />
      </div>

      <.date_with_format date_field={@date_field} format_field={@format_field} />

      <.proposal_row
        id={"proposals-#{@date_field.id}"}
        field={to_string(@date_field.field)}
        proposals={@proposals}
      />
    </div>
    """
  end

  attr :id, :string, required: true
  attr :field, :string, required: true, doc: "what the accept event names the field"
  attr :proposals, :list, required: true
  attr :event, :string, default: "accept-proposal"

  @doc """
  A "Proposed" chip row — the decision_row options row, fed by ticked
  evidence instead of a draft's candidates.

  Chip anatomy is identical to the import form's: only the chosen chip's
  source tag fills lime, everyone else's is bare muted uppercase; one line
  or a list, never a partial wrap.
  """
  def proposal_row(assigns) do
    assigns = assign(assigns, :images?, Enum.any?(assigns.proposals, & &1[:image]))

    ~H"""
    <div
      :if={@proposals != []}
      class={["grid-cols-[4.5rem_minmax(0,1fr)] grid gap-x-2 pl-3", (@images? && "items-start") || "items-baseline"]}
      data-role="proposals"
    >
      <.microlabel class={@images? && "pt-1.5"}>Proposed</.microlabel>

      <div id={@id} phx-hook="fit-or-stack" class="flex flex-wrap items-center gap-1.5">
        <.proposal_chip
          :for={proposal <- @proposals}
          chosen={proposal.chosen}
          event={@event}
          values={%{field: @field, key: proposal.key}}
        >
          <span class={[
            "text-[10px] flex-none uppercase tracking-wide",
            proposal.chosen && "bg-brand-dark rounded-sm px-1 text-zinc-900",
            !proposal.chosen && "text-zinc-500"
          ]}>
            {Enum.join(proposal.providers, ", ")}
          </span>
          <span :if={!proposal[:image]}>{proposal.display}</span>
          <%!-- Choosing between two covers by URL is choosing blind. --%>
          <.image_with_size
            :if={proposal[:image]}
            id={"#{@id}-#{proposal.key}"}
            src={proxied_remote_image_url(proposal.image)}
            class="mt-1 h-20 w-20 rounded-sm object-cover"
          />
        </.proposal_chip>
      </div>
    </div>
    """
  end

  attr :record, :any, required: true
  attr :field, :atom, required: true
  attr :hints, :map, required: true

  @doc """
  Where a field's value came from.

  Reads the pending hint first — an accepted proposal that will be recorded
  on save is the field's future, and amber says "not saved yet". The lock
  toggle this once carried is gone: nothing consumes locks yet (the refresh
  feature they gate is unbuilt), so the toggle was UI for a promise nothing
  tested. The manual-vs-provider semantics are still recorded on save, and
  the lock UI returns if and when a consumer exists.
  """
  def provenance_flag(assigns) do
    assigns =
      assign(assigns,
        hint: assigns.hints[to_string(assigns.field)],
        entry:
          assigns.record && assigns.record.id && Provenance.entry(assigns.record, assigns.field)
      )

    ~H"""
    <%!-- A pending source shows even on an unsaved record — accepting a
        proposal on a New form still records the provider. --%>
    <span :if={@hint || @entry} class="text-xs" data-role="provenance-flag">
      <span :if={@hint} class="text-amber-300">
        will record {source_label(@hint.source)}
      </span>
      <span :if={!@hint && @entry} class="text-zinc-400">
        from {source_label(@entry["source"])}
      </span>
    </span>
    """
  end

  @doc """
  Marks each proposal chosen or not, by comparing what accepting it would
  write against what the form currently holds.

  `current` maps param name → the form's current value; values compare
  string-normalized because one side comes from typed params and the other
  from casts (`%Date{}` vs `"2015-03-12"`).
  """
  def mark_chosen(proposals, current) when is_map(current) do
    Enum.map(proposals, fn proposal ->
      chosen =
        Enum.all?(proposal.params, fn {key, value} ->
          Map.has_key?(current, key) and normalize(current[key]) == normalize(value)
        end)

      Map.put(proposal, :chosen, chosen)
    end)
  end

  @doc """
  Marks entity proposals (authors, narrators, series) chosen when a current
  row already carries that entity's name.
  """
  def mark_present(proposals, current_names) do
    names = MapSet.new(current_names, &String.downcase(String.trim(&1 || "")))

    Enum.map(proposals, fn proposal ->
      Map.put(proposal, :chosen, MapSet.member?(names, String.downcase(proposal.params["name"])))
    end)
  end

  defp normalize(nil), do: ""
  defp normalize(value), do: value |> to_string() |> String.trim()

  # source_words resolves provider ids to display names for everyone now
  defp source_label(source), do: source_words(source)
end
