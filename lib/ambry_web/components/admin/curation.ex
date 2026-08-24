defmodule AmbryWeb.Admin.Curation do
  @moduledoc """
  The edit forms' curation surface: an evidence panel, and fields that grow
  "Proposed" chips from it.

  The import form's vocabulary (`record_row`, `provider_outcomes_row`,
  `research_form`, `proposal_chip`) composed for a record that already exists.
  The differences are the context's: an edit form's fields are not *waiting*
  on anyone, so no state rails, and its evidence is session state rather than
  a stored draft, so the panel remembers nothing after the page is left.

  What an accepted proposal leaves behind is the field's provenance entry,
  worn inline in each field's header.
  """

  use Phoenix.Component

  import AmbryWeb.Admin.Components, only: [disclosure: 1, microlabel: 1]

  import AmbryWeb.Admin.Decisions,
    only: [
      person_research_form: 1,
      provider_outcomes_row: 1,
      proposal_chip: 1,
      record_list: 1,
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
  attr :retrying, :any, default: nil

  attr :scan_files, :boolean,
    default: false,
    doc: "the recording level: its files have something to say, and asking them is not a search"

  @doc """
  The evidence panel: one search, fanned out to every capable provider, its
  results tickable records.

  Sits outside the record's own `<form>`, above it: evidence first, then the
  decisions it feeds. Starts folded, since an edit form is mostly visited for
  reasons that are not curation.

  Reading the files is not searching for the book: one takes milliseconds and
  always has something to say. So the recording level has two buttons rather
  than making "would the embedded cover be better?" cost a fan-out.

  Nothing is editable while it runs. The scrim is the caller's, over the whole
  form, because chips appear under every field a fan-out can fill.
  """
  def evidence_panel(assigns) do
    ~H"""
    <%!-- `open` is pinned server-side once anything has been asked, or a
        LiveView patch would strip the client-toggled attribute and slam the
        panel shut as results arrive. The tags belong in that list too: a fold
        may not close itself because of a button pressed inside it. --%>
    <.disclosure
      class="pl-3 text-sm font-semibold text-zinc-200"
      container_class="space-y-2"
      data-role="evidence-panel"
      open={@evidence.running? or @evidence.searched? or @evidence.tags != nil}
    >
      <:summary_slot>{@title}</:summary_slot>

      <%!-- The query, then who answered, then what they said: a card of
          search results is a search form with its results below it. --%>
      <div class="mt-2 space-y-2 rounded-lg bg-zinc-900 p-4">
        <.research_form
          :if={@level != "person"}
          level={@level}
          fields={@evidence.fields}
          running={@evidence.running?}
          scan_files={@scan_files}
          label={search_words(@evidence, @scan_files)}
        />

        <%!-- A person is searched by name; the research form's
            title/author/narrator fields are the books' vocabulary. The shared
            component, never a copy of it: a second copy drifts. --%>
        <.person_research_form
          :if={@level == "person"}
          event="research"
          name={@evidence.fields["name"]}
          running={@evidence.running?}
        />

        <.provider_outcomes_row
          outcomes={@evidence.outcomes}
          level={@level}
          retrying={@retrying}
          retryable={@level != "person"}
        />

        <.record_list records={@evidence.records} used={&Evidence.used?(@evidence, &1)}>
          <:row :let={record}>
            <.record_row
              record={record}
              used={Evidence.used?(@evidence, record)}
              level={@level}
              event="toggle-evidence"
              note={Evidence.note(@evidence, record)}
            />
          </:row>
        </.record_list>

        <p
          :if={@evidence.searched? and not @evidence.running? and @evidence.records == []}
          class="pl-3 text-sm text-zinc-400"
        >
          Nothing came back. Try different words.
        </p>
      </div>
    </.disclosure>
    """
  end

  # "Search again" presumed a search; a panel that also reads files has two
  # verbs to name and the button that does both should say so.
  defp search_words(_evidence, true), do: "Read files & search"
  defp search_words(%Evidence{searched?: true}, _scan), do: "Search again"
  defp search_words(_evidence, _scan), do: "Search"

  attr :field, FormField, required: true
  attr :label, :string, required: true
  attr :type, :string, default: "text"
  attr :options, :list, default: nil
  attr :class, :any, default: nil, doc: "sizes the control to its content (§7)"
  attr :record, :any, default: nil, doc: "the persisted struct provenance is read from"
  attr :hints, :map, default: %{}, doc: "pending provenance hints, field name → hint"
  attr :proposals, :list, default: [], doc: "what ticked evidence proposes, `:chosen` included"
  attr :revert, :map, default: nil, doc: "the saved value to go back to, when it differs"
  attr :rest, :global, include: ~w(placeholder)

  @doc """
  One provider-fillable scalar: label, where its value came from, the
  control, and what the ticked evidence proposes.

  The header is the import form's "from …" idiom pointed at `Provenance`:
  the recorded source, or an amber pending one when saving will record it.
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
        revert={@revert}
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
  attr :revert, :map, default: nil

  @doc """
  A curated composite date: label, provenance, one date+precision control,
  and combined chips. A chip proposes both halves and accepting settles both,
  so taking the date from one provider and the precision from another is not
  a choice anyone is offered.
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
        revert={@revert}
      />
    </div>
    """
  end

  attr :id, :string, required: true
  attr :field, :string, required: true, doc: "what the accept event names the field"
  attr :proposals, :list, required: true
  attr :event, :string, default: "accept-proposal"

  attr :adds_rows, :boolean,
    default: false,
    doc: "these chips append a row to a list rather than set a field's value"

  attr :revert, :map,
    default: nil,
    doc: ~s(`%{display:, image:}` for the saved value — rendered only while the field differs)

  @doc """
  A "Proposed" chip row — the decision_row options row, fed by ticked
  evidence instead of a draft's candidates.

  Chip anatomy is identical to the import form's: only the chosen chip's
  source tag fills lime, and it is one line or a list, never a partial wrap.

  `adds_rows` says these chips credit a person or join a series rather than
  fill a field, which changes what a chosen one means: not "the field holds
  this" but "the record already has it".
  """
  def proposal_row(assigns) do
    assigns = assign(assigns, :images?, Enum.any?(assigns.proposals, & &1[:image]))

    ~H"""
    <div
      :if={@proposals != [] or @revert}
      class={["grid-cols-[4rem_minmax(0,1fr)] grid gap-x-2 pl-3", (@images? && "items-start") || "items-baseline"]}
      data-role="proposals"
    >
      <.microlabel class={@images? && "pt-1.5"}>Proposed</.microlabel>

      <div id={@id} phx-hook="fit-or-stack" class="flex flex-wrap items-center gap-1.5">
        <.proposal_chip
          :for={proposal <- @proposals}
          chosen={proposal.chosen}
          inert={@adds_rows}
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

        <%!-- The way back: a chip changes a field in one click, so the saved
            value is offered as an option too. Ghost, because it is the escape
            hatch rather than a proposal, and absent while the field still
            holds what was saved. --%>
        <.proposal_chip
          :if={@revert}
          chosen={false}
          ghost
          event="revert-field"
          values={%{field: @field}}
          title="Go back to the saved value"
        >
          <span class="text-[10px] flex-none uppercase tracking-wide text-zinc-500">saved</span>
          <span :if={!@revert[:image]}>{@revert.display}</span>
          <.image_with_size
            :if={@revert[:image]}
            id={"#{@id}-saved"}
            src={@revert.image}
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

  Reads the pending hint first: an accepted proposal that will be recorded on
  save is the field's future, and amber says "not saved yet".

  Provenance records manual-vs-provider on save. Nothing consumes the lock it
  implies yet, so there is no lock control here.
  """
  def provenance_flag(assigns) do
    entry = assigns.record && assigns.record.id && Provenance.entry(assigns.record, assigns.field)

    assigns =
      assign(assigns, hint: news(assigns.hints[to_string(assigns.field)], entry), entry: entry)

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
  The names a record's rows already carry, for `mark_present/2`.

  Asked of the context row by row rather than found in a preloaded list of
  every author in the library — the same lookup `EntityResolver`'s `fetch`
  makes, for the same reason.

  `get_field/2` and not `get_assoc/2`: a row removed with the ✕ is still in
  the association, marked for replacement, and counting it would keep a chip
  reporting a credit the operator just took off.
  """
  def current_labels(changeset, assoc, key, fetch, nested \\ nil) do
    changeset
    |> Ecto.Changeset.get_field(assoc)
    |> Enum.map(fn row ->
      row
      |> Map.get(key)
      |> fetch.()
      |> option_label()
      |> case do
        nil -> nested && brought_name(row, nested)
        label -> label
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  # The name of the record a row brought with it, if it brought one. A linked
  # row's association is simply not loaded, which is not an answer.
  defp brought_name(row, nested) do
    case Map.get(row, nested) do
      %{name: name} when is_binary(name) -> name
      _linked_or_absent -> nil
    end
  end

  @doc """
  The name a row's nested record carries, if it brought one.

  A row either points at a record or brings a new one (`Ambry.Ecto.EntityRef`),
  and the picker has to render whichever it is: the label of what it points
  at, or the name of what it brought.
  """
  def staged_name(row_form, assoc) do
    case Ecto.Changeset.get_change(row_form.source, assoc) do
      nil -> nil
      changeset -> Ecto.Changeset.get_field(changeset, :name)
    end
  end

  @doc """
  Whether a list already credits this name, however it says so.

  A row may point at a record or merely name one (`Ambry.Ecto.EntityRef`), and
  both count: a chip that has been clicked once is reporting a credit that is
  staged rather than saved, and clicking it again must not stage it twice.
  """
  def credits_name?(changeset, assoc, key, fetch, name_key, name) do
    wanted = normalized(name)

    changeset
    |> current_labels(assoc, key, fetch, name_key)
    |> Enum.any?(&(normalized(&1) == wanted))
  end

  defp normalized(nil), do: nil
  defp normalized(name), do: name |> String.trim() |> String.downcase()

  defp option_label(%{label: label}), do: label
  defp option_label({label, _id}), do: label
  defp option_label(nil), do: nil

  @doc """
  The form's params with one row appended to a list.

  **Built from the params, not from the changeset.** A row may carry a whole
  nested record it is about to create, and rebuilding from the changeset keeps
  the columns it knows about and drops that. The params are what the form
  already holds, so appending to them adds a row and changes nothing else, and
  the sort and drop lists travel untouched for Ecto to reconcile.

  Before anything is posted the params are empty and the rows come from the
  changeset: ids only, which is all an untouched row is.
  """
  def append_row(form, assoc, new_row) do
    key = to_string(assoc)
    rows = rows(form, key, assoc)
    next = rows |> Map.keys() |> Enum.map(&as_integer/1) |> Enum.max(fn -> -1 end) |> Kernel.+(1)

    Map.put(form.params, key, Map.put(rows, to_string(next), new_row))
  end

  defp rows(form, key, assoc) do
    case Map.get(form.params, key) do
      rows when is_map(rows) ->
        rows

      _nothing_posted_yet ->
        form.source
        |> Ecto.Changeset.get_field(assoc)
        |> Enum.with_index()
        |> Map.new(fn {row, index} -> {to_string(index), %{"id" => to_string(row.id)}} end)
    end
  end

  defp as_integer(key) do
    case Integer.parse(to_string(key)) do
      {integer, ""} -> integer
      _not_a_number -> -1
    end
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

  # A hint naming the source already recorded is not news: clicking the chip
  # whose value is already saved would turn the flag amber and announce a
  # change that is not one.
  defp news(nil, _entry), do: nil

  defp news(hint, %{"source" => source} = entry) do
    if !(hint.source == source and to_string(hint.record) == to_string(entry["record"])) do
      hint
    end
  end

  defp news(hint, _nothing_recorded), do: hint

  defp source_label(source), do: source_words(source)
end
