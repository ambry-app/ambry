defmodule AmbryWeb.Admin.ChapterEditor do
  @moduledoc """
  The chapter editor: one card, shared by the media form and the inbox
  import form — because chapters are curated the same way at the library
  door and after it.

  A **marker** is a position and is only meaningful against the actual
  bytes — provider chapter times describe their own retail edition and
  drift by minutes across a book — so markers come from the files and
  nothing else may write them. A **title** is just a name, so it comes from
  wherever the best one is, per row.

  Title imports follow the evidence model rather than owning a search: a
  ticked record carrying an ASIN grows a proposal chip under the card, and
  the fetched titles render **into the rows themselves** — a proposed-title
  cell beside each title input, inside the card's own scroll — with one
  Take/Cancel header. There is no separate preview surface: the rows are
  the preview, and nothing lands until Take.

  **Titles are only taken when the counts match.** A provider list that
  doesn't pair one-to-one with the markers stays visible (the proposed
  column shows where the two lists diverge, which is what to fix) but
  cannot be applied — an operator call, superseding the earlier
  pour-through-alignment behavior.

  Both hosting LiveViews speak the same event vocabulary:
  `fetch-chapter-titles`, `apply-chapter-titles`, `cancel-chapter-import`.

  See the roadmap's 1h.
  """
  use AmbryWeb, :html

  import AmbryWeb.Admin.Components
  import AmbryWeb.Admin.Decisions, only: [proposal_chip: 1]

  alias Ambry.Media.Chapters.Merge
  alias Ambry.Media.Media.Chapter
  alias Ambry.Metadata.Provider
  alias Ambry.Metadata.Search, as: MetadataSearch
  alias Ecto.Changeset
  alias Phoenix.LiveView.AsyncResult

  @doc """
  The pending title fetch, kept in one assign (`nil` when nothing is
  pending): `%{chip: chip, result: %AsyncResult{}}`, where the ok result is
  `%{incoming:, source:}`.
  """
  def pending_import(chip), do: %{chip: chip, result: AsyncResult.loading()}

  @doc """
  Applies an async outcome to the pending import in
  `assigns.chapter_import`. A cancel can race a landing async — a result
  for a header that is no longer open is dropped, not resurrected.
  """
  def update_pending_import(socket, fun) do
    case socket.assigns.chapter_import do
      %{result: result} = pending ->
        Phoenix.Component.assign(socket, chapter_import: %{pending | result: fun.(result)})

      _stale ->
        socket
    end
  end

  @doc """
  An async exit as the sentence the pending header shows.
  """
  def async_fail({exception, _stack}) when is_exception(exception),
    do: Exception.message(exception)

  def async_fail(reason), do: inspect(reason)

  @doc """
  Fetches a chapter list by ASIN from every chapter-capable provider on the
  registry, for a `start_async`. Raises with the per-provider outcomes when
  nobody has one, so the header can say who was asked and what went wrong.
  """
  def fetch_chapter_titles(asin) do
    {found, outcomes} = MetadataSearch.chapters(asin)

    case Enum.find(found, fn {_entry, chapters} -> chapters.chapters != [] end) do
      {entry, chapters} ->
        %{incoming: incoming_from_provider(chapters), source: "provider:#{entry.id}"}

      nil ->
        raise chapters_failure(outcomes)
    end
  end

  defp chapters_failure([]), do: "No enabled provider can fetch chapter lists."

  defp chapters_failure(outcomes) do
    Enum.map_join(outcomes, " · ", fn
      %{"status" => "ok", "name" => name} -> "#{name}: no chapters"
      %{"status" => "failed", "name" => name, "reason" => reason} -> "#{name}: #{reason}"
    end)
  end

  # ---------------------------------------------------------------------------
  # The card
  # ---------------------------------------------------------------------------

  attr :form, :any, required: true

  @doc """
  The marker-source input, carried through every render so the form keeps
  submitting what it shows. Bare, not `<.input type="hidden">`: that wraps
  its control in a spaced container, which in a `space-y` stack shows up as
  an extra gap drawn by something invisible.
  """
  def marker_source_input(assigns) do
    ~H"""
    <input
      type="hidden"
      name={@form[:chapter_marker_source].name}
      value={@form[:chapter_marker_source].value}
    />
    """
  end

  attr :form, :any,
    required: true,
    doc: "a form whose :chapters embed uses chapters_sort/chapters_drop"

  attr :pending, :any, default: nil, doc: "the pending title fetch, or nil"

  attr :rail, :string,
    default: nil,
    doc: "the decision rail, where this card is one of a tree of decisions"

  slot :flag, doc: "a provenance flag, worn on the source line"
  slot :proposals, doc: "the title chips, inside the card after the rows"

  @doc """
  The whole editor as one card: a source line, then the rows in their own
  scroll, with the pending title fetch rendered into them — a proposed
  column and a Take/Cancel header — rather than as a second surface.

  In the inbox it wears a rail like every other decision card. It was the one
  card in the tree that wore none, so the operator's eye ran down a column of
  rails and found a gap where chapters should have been — reading as "not a
  decision" for something the footer was counting all along. The media form
  passes none: nothing there is staged, so there is no settledness to encode.
  """
  def chapter_rows(assigns) do
    markers = current_chapters(assigns.form)

    incoming =
      case assigns.pending do
        %{result: %AsyncResult{ok?: true, result: %{incoming: incoming}}} -> incoming
        _none -> nil
      end

    assigns =
      assigns
      |> assign(:markers, markers)
      |> assign(:incoming, incoming)
      |> assign(:takeable, incoming && length(incoming) == length(markers))
      |> assign(:proposed, incoming && proposed_by_row(markers, incoming))

    ~H"""
    <div class="space-y-2">
      <div class={["space-y-3 rounded-lg bg-zinc-900 p-4", @rail && "#{@rail} border-l-4"]}>
        <%!-- Where the markers came from used to be spelled out here
            ("Markers read from the files' own chapter marks · titles: 40
            embedded."), which restated what every row already shows in its
            own source column and pushed the rows down a line on every form
            that carries them. The provenance flag is the part that says
            something the rows can't, so it is what is left. --%>
        <p :if={@flag != []} class="flex items-baseline gap-2 pl-3 text-sm text-zinc-400">
          {render_slot(@flag)}
        </p>

        <.pending_header :if={@pending} pending={@pending} markers={@markers} takeable={@takeable} />

        <%!-- pr-2: the scrollbar draws at the container's edge, and without
            a gutter it sits on top of the rows' ✕ column --%>
        <div :if={@markers != []} class="max-h-96 space-y-2 overflow-y-auto pr-2">
          <.inputs_for :let={chapter_form} field={@form[:chapters]}>
            <.sort_input field={@form[:chapters_sort]} index={chapter_form.index} />
            <%!-- Carried through every re-render on purpose: the form only
                submits what it renders, so a source dropped here would be
                re-derived on the next keystroke and quietly un-answer a
                question the operator (or a merge) already answered. --%>
            <input
              type="hidden"
              name={chapter_form[:title_source].name}
              value={chapter_form[:title_source].value}
            />

            <div class={[
              "grid items-start gap-2",
              (@incoming && "grid-cols-[7rem_minmax(0,1fr)_minmax(0,1fr)_3.5rem_auto]") ||
                "grid-cols-[7rem_minmax(0,1fr)_3.5rem_auto]"
            ]}>
              <.input field={chapter_form[:time]} show_errors={false} />
              <.input field={chapter_form[:title]} show_errors={false} />

              <%!-- What the fetched list proposes for this row. Aligned by
                  duration when the counts differ, so the gap shows up at the
                  marker that has no counterpart — which is the row to fix. --%>
              <p :if={@incoming} class="pt-[10px] truncate pl-3 text-sm text-zinc-400">
                {case Map.get(@proposed, chapter_form.index) do
                  nil -> "—"
                  title -> title
                end}
              </p>

              <div class="pt-[10px]">
                <.microlabel>{title_source_label(chapter_form[:title_source].value)}</.microlabel>
              </div>

              <.delete_button
                field={@form[:chapters_drop]}
                index={chapter_form.index}
                class="pt-[10px]"
              />
            </div>
          </.inputs_for>
        </div>

        <p :if={@markers == []} class="pl-3 text-sm text-zinc-400">
          No chapter rows.
        </p>

        {render_slot(@proposals)}
      </div>

      <div>
        <.add_button field={@form[:chapters_sort]}>Add chapter</.add_button>
        <.delete_input field={@form[:chapters_drop]} />
      </div>
    </div>
    """
  end

  attr :pending, :map, required: true
  attr :markers, :list, required: true
  attr :takeable, :boolean, required: true

  # The one header the pending fetch gets: what arrived (or why it didn't),
  # and Take/Cancel. Take only exists when the lists pair one-to-one.
  defp pending_header(assigns) do
    ~H"""
    <div class="space-y-2" data-role="chapter-import">
      <.loading :if={!@pending.result.ok? && !@pending.result.failed}>
        Fetching chapter titles…
      </.loading>

      <.error :if={@pending.result.failed}>{fail_message(@pending.result.failed)}</.error>

      <%= if @pending.result.ok? do %>
        <p :if={@takeable} class="pl-3 text-sm text-zinc-300">
          {n_things(@pending.result.result.incoming, "title")} for “{@pending.chip.title}”. Each
          row shows how its title lands.
        </p>

        <p :if={!@takeable} class="flex items-baseline gap-1.5 pl-3 text-sm text-amber-300">
          <.icon name="fa-triangle-exclamation" class="h-3.5 w-3.5 flex-none self-center" />
          {n_things(@pending.result.result.incoming, "title")} for {n_things(@markers, "marker")}.
          Titles are only taken when the counts match; the proposed column shows where the lists
          diverge.
        </p>
      <% end %>

      <div class="flex flex-wrap items-center gap-2">
        <.button
          :if={@takeable}
          color={:zinc}
          size={:sm}
          type="button"
          phx-click="apply-chapter-titles"
        >
          Take these titles
        </.button>

        <.button color={:zinc} size={:sm} type="button" phx-click="cancel-chapter-import">
          Cancel
        </.button>
      </div>
    </div>
    """
  end

  # Which incoming title lands on which row. Index-wise when the counts
  # match; otherwise aligned by duration (`Merge.align/2`) purely so the
  # display puts the gap at the unpaired marker instead of shifting
  # everything after it — a mismatched list is never *applied*.
  defp proposed_by_row(markers, incoming) do
    if length(markers) == length(incoming) do
      Map.new(0..(length(markers) - 1)//1, &{&1, Enum.at(incoming, &1).title})
    else
      markers
      |> Merge.align(incoming)
      |> Map.new(fn
        {marker_index, nil} -> {marker_index, nil}
        {nil, _incoming_index} -> {nil, nil}
        {marker_index, incoming_index} -> {marker_index, Enum.at(incoming, incoming_index).title}
      end)
    end
  end

  attr :id, :string, required: true
  attr :chips, :list, required: true, doc: "maps with :asin, :title, :providers, :chosen"

  attr :file, :map,
    default: nil,
    doc: "the files' own list as a chip (%{chosen: boolean}), or nil when they carry none"

  @doc """
  What the ticked evidence proposes for the titles: one chip per distinct
  ASIN, in the standard proposal anatomy. A chip is not a value here — it
  names an edition whose chapter list is one fetch away, so clicking loads
  the proposed column rather than applying anything.

  ## The files are a proposal too

  The first chip is the files' own list, and it applies immediately, the way
  a credit's "go back to what the records proposed" chip does. Without it the
  operator who wanted exactly what the files carry — the common case, since
  that is what the rows are seeded from — had no way to *say so*: the card
  only reached `:reviewed` by editing a row, so agreeing with it cost a
  pointless edit and disagreeing was the only settled state.

  It is chosen when the rows already match the files, which makes it a
  statement as well as a control: this is still what the files said.
  """
  def chapter_title_chips(assigns) do
    ~H"""
    <div
      :if={@chips != [] or @file}
      class="grid-cols-[4rem_minmax(0,1fr)] grid items-baseline gap-x-2 pl-3"
      data-role="proposals"
    >
      <.microlabel>Proposed</.microlabel>

      <div id={@id} phx-hook="fit-or-stack" class="flex flex-wrap items-center gap-1.5">
        <.proposal_chip
          :if={@file}
          chosen={@file.chosen}
          event="take-file-chapters"
          title="take the timestamps and titles the files carry"
        >
          <span class={[
            "text-[10px] flex-none uppercase tracking-wide",
            @file.chosen && "bg-brand-dark rounded-sm px-1 text-zinc-900",
            !@file.chosen && "text-zinc-500"
          ]}>
            files
          </span>
          <span>timestamps and titles as read</span>
        </.proposal_chip>

        <.proposal_chip
          :for={chip <- @chips}
          chosen={chip.chosen}
          event="fetch-chapter-titles"
          values={%{asin: chip.asin}}
          title={"Chapter titles for ASIN #{chip.asin}"}
        >
          <span class={[
            "text-[10px] flex-none uppercase tracking-wide",
            chip.chosen && "bg-brand-dark rounded-sm px-1 text-zinc-900",
            !chip.chosen && "text-zinc-500"
          ]}>
            {Enum.join(chip.providers, ", ")}
          </span>
          <span>titles for “{chip.title}”</span>
        </.proposal_chip>
      </div>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Vocabulary
  # ---------------------------------------------------------------------------

  @doc """
  How a title got its name, in one muted word for a dense row.

  `:generated` deliberately reads "auto" rather than naming a source: it is
  the absence of one.
  """
  def title_source_label(:generated), do: "auto"
  def title_source_label(:embedded), do: "file"
  def title_source_label(:filename), do: "name"
  def title_source_label(:provider), do: "provider"
  def title_source_label(:manual), do: "typed"
  def title_source_label("generated"), do: "auto"
  def title_source_label("embedded"), do: "file"
  def title_source_label("filename"), do: "name"
  def title_source_label("provider"), do: "provider"
  def title_source_label("manual"), do: "typed"
  def title_source_label(_unrecorded), do: nil

  defp n_things(list, word) when length(list) == 1, do: "1 #{word}"
  defp n_things(list, word), do: "#{length(list)} #{word}s"

  defp fail_message(message) when is_binary(message), do: message

  defp fail_message({exception, _stacktrace}) when is_exception(exception),
    do: Exception.message(exception)

  defp fail_message(reason), do: inspect(reason)

  # ---------------------------------------------------------------------------
  # Form logic, shared by both hosting LiveViews
  # ---------------------------------------------------------------------------

  @doc """
  What the chapter list is right now, read off the form so it follows
  unsaved edits — an operator who has just nudged three markers and not
  saved yet means *those* markers, and pouring titles onto the stale ones
  would silently undo the nudge.
  """
  def current_chapters(form) do
    form.source |> Changeset.apply_changes() |> Map.fetch!(:chapters)
  end

  @doc """
  Whether a pending fetch may be applied: only when the lists pair
  one-to-one. The handler's guard, so a stale click can't pour a mismatched
  list.
  """
  def takeable?(incoming, markers), do: length(incoming) == length(markers)

  @doc """
  A chapter struct as form params — how an applied import lands on the form.

  An import replaces the whole list, so callers must also drop any sort
  param that was tracking the old rows: it would re-order the new ones
  against positions that no longer exist.
  """
  def chapter_params(chapter) do
    %{
      "time" => to_string(chapter.time),
      "title" => chapter.title,
      "title_source" => chapter.title_source && to_string(chapter.title_source)
    }
  end

  @doc """
  Typing over a title is an answer, and an answer has to survive the next
  merge — which it only does if it stops claiming a source that would let
  the merge overwrite it.

  The comparison belongs here rather than in the changeset because a
  chapter is an embed with no primary key: Ecto replaces the whole list on
  every cast, so at the schema level *every* title looks like a change from
  nil and there is nothing to compare against. What the operator just
  edited is only knowable against what the form was showing them, which is
  what `showing` is.
  """
  def mark_typed_titles(%{"chapters" => chapters} = params, showing) when is_map(chapters) do
    showing = List.to_tuple(showing)

    Map.put(
      params,
      "chapters",
      Map.new(chapters, fn {index, chapter} ->
        {index, mark_typed(chapter, at(showing, index))}
      end)
    )
  end

  def mark_typed_titles(params, _showing), do: params

  defp mark_typed(chapter, nil), do: chapter

  defp mark_typed(chapter, showing) do
    # An explicitly changed source is somebody answering deliberately (an
    # import, or the renumbering below); only a title that moved on its own
    # is the operator typing.
    if chapter["title"] != showing.title and
         chapter["title_source"] == to_string(showing.title_source) do
      Map.put(chapter, "title_source", "manual")
    else
      chapter
    end
  end

  defp at(showing, index) do
    case Integer.parse(index) do
      {index, ""} when index < tuple_size(showing) -> elem(showing, index)
      _out_of_range_or_not_an_index -> nil
    end
  end

  @doc """
  The generated floor is a *position*, so it has to stop saying "Chapter 7"
  the moment a row is inserted above it — see `Chapter.renumber_changesets/1`.
  """
  def renumber_generated(changeset) do
    case Changeset.get_change(changeset, :chapters) do
      nil ->
        changeset

      chapters ->
        Changeset.put_change(changeset, :chapters, Chapter.renumber_changesets(chapters))
    end
  end

  @doc """
  A provider's chapter list as merge input. The times are read for exactly
  one purpose — computing the durations the mismatch display aligns by —
  and are then thrown away; only the titles land.
  """
  def incoming_from_provider(%Provider.Chapters{chapters: chapters}) do
    Enum.map(chapters, fn chapter ->
      %{
        title: chapter.title,
        time: chapter.start_offset_ms |> Decimal.new() |> Decimal.div(1000) |> Decimal.round(2)
      }
    end)
  end

  @doc """
  The chips the ticked evidence offers: one per distinct ASIN, first
  occurrence keeping the identity, `chosen` when its titles were the last
  applied this session.
  """
  def title_chips(used_records, applied_asin) do
    used_records
    |> Enum.filter(&present?(&1["asin"]))
    |> Enum.uniq_by(& &1["asin"])
    |> Enum.map(fn record ->
      %{
        asin: record["asin"],
        title: record["title"] || record["asin"],
        providers: [record["provider_name"] || record["source"]],
        chosen: record["asin"] == applied_asin
      }
    end)
  end

  defp present?(nil), do: false
  defp present?(string) when is_binary(string), do: String.trim(string) != ""
end
