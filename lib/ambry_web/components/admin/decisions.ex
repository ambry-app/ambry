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

  import AmbryWeb.Admin.Components,
    only: [badge: 1, busy_overlay: 1, disclosure: 1, microlabel: 1]

  import AmbryWeb.CoreComponents

  alias Ambry.Inbox.Draft.Credit
  alias Ambry.Inbox.Draft.Field
  alias Ambry.Inbox.Draft.GroupLink
  alias Ambry.Inbox.Draft.PersonDecision
  alias Ambry.Inbox.Draft.SeriesLink
  alias Ambry.Inbox.Draft.Tier
  alias AmbryWeb.Components.EntityResolver

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
    <div
      :if={@outcomes != []}
      class="grid-cols-[4rem_minmax(0,1fr)] grid items-baseline gap-x-2 pl-3"
      data-role="provider-outcomes"
    >
      <%!-- Named for what it is now that it sits under the search rather than
            after the records: these are what the search came back with. --%>
      <.microlabel>Results</.microlabel>

      <div class="flex flex-wrap items-center gap-1.5">
        <%!-- A count is information, not an option — filled and quiet, so it
            can't be mistaken for the clickable proposal chips nearby. --%>
        <span
          :for={outcome <- @outcomes}
          :if={outcome["status"] != "failed"}
          class="bg-white/5 rounded-sm px-2 py-0.5 text-xs tabular-nums text-zinc-400"
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
          class="bg-red-400/10 rounded-sm px-2 py-0.5 text-xs text-red-300 hover:bg-red-400/20 disabled:opacity-50"
        >
          {outcome["name"]}: {if @retrying == outcome["id"],
            do: "asking again…",
            else: "couldn't be reached, retry"}
        </button>

        <span
          :for={outcome <- @outcomes}
          :if={outcome["status"] == "failed" and not @retryable}
          title={outcome["reason"]}
          class="bg-red-400/10 rounded-sm px-2 py-0.5 text-xs text-red-300"
        >
          {outcome["name"]}: couldn't be reached
        </span>
      </div>
    </div>
    """
  end

  # Where a candidate stops being an alternative and starts being noise. Sits
  # deliberately at the boundary rather than below it: on the operator's
  # Martian the contradicted Wil Wheaton editions score exactly 0.5, and they
  # are the *other real recording* of that book — precisely what somebody
  # opens this list to find. One constant, tune it here.
  @worth_showing 0.5

  attr :records, :list, required: true
  attr :used, :any, required: true, doc: "fn record -> boolean, the ticked test"
  slot :row, required: true, doc: "renders one record; receives the record"

  @doc """
  A level's records, with the junk folded away.

  Eight rows all wearing the same weight is how a 6% study guide got read as
  an alternative worth considering. Below `#{@worth_showing}` a record is not
  a rival reading of the book, it is a search result that happened to share a
  word — so it goes behind a link and stops competing for the eye.

  **A ticked record is never hidden**, whatever it scores. Folding away
  something the operator has chosen would leave the form showing a decision
  with no visible cause, and a low score is exactly why somebody would have
  gone looking for it by hand.
  """
  def record_list(assigns) do
    {shown, folded} = Enum.split_with(assigns.records, &worth_showing?(&1, assigns.used))

    assigns = assign(assigns, shown: shown, folded: folded)

    ~H"""
    <%= for record <- @shown do %>
      {render_slot(@row, record)}
    <% end %>

    <.disclosure
      :if={@folded != []}
      summary={worse_matches_label(@folded)}
      container_class="space-y-2"
      data-role="worse-matches"
    >
      <div class="space-y-2 pt-2">
        <%= for record <- @folded do %>
          {render_slot(@row, record)}
        <% end %>
      </div>
    </.disclosure>
    """
  end

  # An *unscored* record is not a weak one — a record staged before its level
  # ranked anything carries no score, and reading a missing score as zero
  # would fold it away unread.
  defp worth_showing?(record, used) do
    case record["score"] do
      score when is_number(score) -> score >= @worth_showing or used.(record)
      _unscored -> true
    end
  end

  defp worse_matches_label([_one]), do: "Show 1 worse match"
  defp worse_matches_label(folded), do: "Show #{length(folded)} worse matches"

  attr :record, :map, required: true
  attr :used, :boolean, required: true
  attr :level, :string, default: nil
  attr :event, :string, default: "toggle-source"
  attr :person_key, :string, default: nil, doc: "set for person records — routes the toggle"
  attr :working, :boolean, default: false

  attr :note, :string,
    default: nil,
    doc: ~s(what this record already gave the library record — "filled title · published")

  @doc """
  One provider record, and whether it counts.

  Not an identity — evidence. Hardcover and rreading-glasses both holding a
  record of one book is the normal case, not a duplicate to clean up, and each
  knows things the other doesn't. Ticking both is how the description comes
  from one and the cover from the other.
  """
  def record_row(assigns) do
    ~H"""
    <%!-- pl-3, not p-2.5: the checkbox sits on the container's text rail,
        like the summary text and microlabels around these cards. --%>
    <label
      class={[
        "flex cursor-pointer items-start gap-3 rounded-md py-2.5 pr-2.5 pl-3",
        @used && "bg-brand-dark/10 ring-brand-dark/50 ring-2 ring-inset",
        !@used && "bg-zinc-800/60 hover:bg-zinc-800"
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
        class="mt-1 h-4 w-4 flex-none rounded-sm border-zinc-600 bg-zinc-700 text-lime-600 focus:ring-lime-500"
      />
      <%!-- Identification, not selection: the cover or face that tells this
          record apart, visible BEFORE ticking — the chips below remain the
          place a photo is chosen.

          The box is always 48×48 and the image is `object-contain` inside it.
          Cropping to fill turned every portrait jacket into a square, which
          is the one thing an operator is looking at these for — square art is
          the audiobook and a portrait is the print cover, and `object-cover`
          made those two indistinguishable. The box is rendered even with
          nothing to put in it, so the titles down the list stay on one rail
          instead of stepping left whenever a record has no art. --%>
      <span class="group/zoom relative -my-0.5 h-12 w-12 flex-none">
        <img
          :if={thumb = record_thumb(@record)}
          src={thumb}
          class="h-full w-full rounded-sm object-contain"
          loading="lazy"
        />
        <span
          :if={!record_thumb(@record)}
          class="bg-zinc-800/80 flex h-full w-full items-center justify-center rounded-sm"
          title="No image"
        >
          <.icon name="fa-image" class="h-4 w-4 text-zinc-600" />
        </span>
        <span
          :if={thumb = record_thumb(@record)}
          data-zoomable
          data-full={thumb}
          title="View full size"
          class="bg-black/70 absolute right-0.5 bottom-0.5 hidden cursor-zoom-in rounded-sm p-0.5 group-hover/zoom:flex"
        >
          <.icon name="fa-magnifying-glass" class="h-3 w-3 text-zinc-100" />
        </span>
      </span>
      <div class="min-w-0 flex-grow">
        <%!-- Which database said this is the first thing an operator checks,
              and it used to ride at the end of the facts line, where it was
              the first thing truncation took. It is a fact about the record
              rather than one of the record's own, so it wears the badge
              costume and holds its width; the title gives way instead. --%>
        <%!-- A div, not a p: `<.badge>` renders a div, and a div inside a
              paragraph makes the parser close the paragraph early — which
              put the badge on a line of its own instead of beside the
              title. --%>
        <div class="flex items-baseline gap-2 text-sm font-medium">
          <span class="min-w-0 truncate">{candidate_title(@record)}</span>

          <span
            :if={@note}
            class="bg-brand-dark/15 flex-none rounded-sm px-1.5 text-xs font-normal text-lime-300"
            data-role="record-note"
          >
            {@note}
          </span>

          <.badge
            :if={candidate_origin(@record)}
            color={:gray}
            class="flex-none text-xs font-normal"
            data-role="record-source"
          >
            {candidate_origin(@record)}
          </.badge>
        </div>
        <p class="truncate text-xs text-zinc-400">{candidate_facts(@record)}</p>
      </div>
      <span :if={@working} class="flex-none pt-0.5 text-xs text-zinc-400">
        fetching…
      </span>
      <%!-- The meter makes the ranking visible before the number is read —
            eight cards with bare percentages all carried identical visual
            weight whether they were a 100% match or a 6% study guide. --%>
      <span :if={!@working && @record["score"]} class="flex flex-none flex-col items-end gap-1 pt-0.5">
        <span class="text-xs tabular-nums text-zinc-400">
          {round(@record["score"] * 100)}%
        </span>
        <span class="h-1 w-16 overflow-hidden rounded-full bg-zinc-700">
          <span
            class={["block h-full rounded-full", meter_color(@record["score"])]}
            style={"width: #{round(@record["score"] * 100)}%"}
          />
        </span>
      </span>
    </label>
    """
  end

  defp record_thumb(record) do
    proxied_remote_image_url(record["cover_url"] || List.first(record["images"] || []))
  end

  # High reads as the accent, the murky middle as a warning, and junk as
  # neutral — the same bands the matcher's own trust thresholds use.
  defp meter_color(score) when score >= 0.75, do: "bg-brand-dark"
  defp meter_color(score) when score >= 0.4, do: "bg-amber-400"
  defp meter_color(_score), do: "bg-zinc-600"

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
        "flex items-start gap-3 rounded-md p-3",
        @linked && "bg-brand-dark/10 ring-brand-dark/50 ring-2 ring-inset",
        !@linked && "bg-zinc-800/60"
      ]}
      data-role="local-book"
      data-linked={@linked && "true"}
    >
      <div class="min-w-0 flex-grow">
        <div class="flex items-baseline gap-2 text-sm font-semibold">
          <span class="min-w-0 truncate">{candidate_title(@book)}</span>

          <.badge
            :if={candidate_origin(@book)}
            color={:gray}
            class="flex-none text-xs font-normal"
            data-role="record-source"
          >
            {candidate_origin(@book)}
          </.badge>
        </div>
        <p class="truncate text-xs text-zinc-400">{candidate_facts(@book)}</p>
      </div>

      <button
        :if={!@linked}
        type="button"
        phx-click="link-book"
        phx-value-id={@book["id"]}
        class={action_classes(:zinc, "flex-none")}
      >
        Yes, another edition of this
      </button>

      <span :if={@linked} class="flex-none text-xs text-zinc-400">using this book</span>
    </div>
    """
  end

  attr :at, :string,
    default: nil,
    doc: "where this renders — DOM ids key on place, not person; nil where there is only one"

  attr :person_key, :string,
    default: nil,
    doc: "routes the search to one person; nil where the surface is about a single person"

  attr :name, :string,
    default: nil,
    doc: "the name these records were searched for — not the person's own name"

  attr :event, :string, default: "research-person"
  attr :label, :string, default: "Search again"
  attr :running, :boolean, default: false

  @doc """
  The person level's search-again form — the work-level pattern with a name
  where the work has title and author.

  The box holds the *query*, exactly as `research_form`'s holds its fields.
  It used to render the person's name decision, so searching for anything else
  worked and then snapped back to the pre-filled name the moment the results
  landed — the one moment the operator needs to see what produced them. The
  two are genuinely different questions: searching "Robert Galbraith" for a
  person the import will create as "J.K. Rowling" is the case this form is
  for, and neither answer should overwrite the other.

  The person edit form hand-wrote this same markup, which is how the two
  drifted: the copy there grew a three-way button label the inbox never got,
  and a fix to either reached only half the people searches in the admin.
  One component, parameterised by the two things that genuinely differ —
  which event routes it, and whether there is a person key to route *to*.
  """
  def person_research_form(assigns) do
    ~H"""
    <form
      id={["research-person", @at] |> Enum.reject(&is_nil/1) |> Enum.join("-")}
      phx-submit={@event}
      class="flex flex-wrap items-end gap-2"
    >
      <input :if={@person_key} type="hidden" name="key" value={@person_key} />

      <label class="text-xs text-zinc-400">
        <span class="block pl-3">name</span>
        <input type="text" name="name" value={@name} class={input_classes("mt-1 block")} />
      </label>

      <.button color={:zinc} type="submit" disabled={@running}>
        {if @running, do: "Searching…", else: @label}
      </.button>
    </form>
    """
  end

  attr :level, :string, required: true
  attr :fields, :map, required: true
  attr :running, :boolean, default: false

  attr :label, :string,
    default: "Search again",
    doc: ~s(the edit forms' fresh panel says "Search" — nothing was searched yet)

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

      <%!-- The label text is railed; the input below it stays a box on the
          box edge, so the pl-3 lives on a span, not the label. --%>
      <label class="text-xs text-zinc-400">
        <span class="block pl-3">title</span>
        <input
          type="text"
          name="title"
          value={@fields["title"]}
          class={input_classes("mt-1 block")}
        />
      </label>

      <label class="text-xs text-zinc-400">
        <span class="block pl-3">author</span>
        <input
          type="text"
          name="author"
          value={@fields["author"]}
          class={input_classes("mt-1 block")}
        />
      </label>

      <label :if={@level == "recording"} class="text-xs text-zinc-400">
        <span class="block pl-3">narrator</span>
        <input
          type="text"
          name="narrator"
          value={@fields["narrator"]}
          class={input_classes("mt-1 block")}
        />
      </label>

      <%!-- Beside full-height inputs, so it is one: adjacent bar controls
          share exact height (§7) — the sm action costume left this button
          short next to every input it touches. --%>
      <.button color={:zinc} type="submit" disabled={@running}>
        {if @running, do: "Searching…", else: @label}
      </.button>
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
    |> Enum.join(" by ")
  end

  @doc """
  A candidate's distinguishing facts, in one line.

  Narrator and year lead because they are what tell two recordings of one work
  apart — the whole reason the recording level exists.

  **Which database said so is not one of them.** It rode at the end of this
  line for a while, which is precisely where a truncated line loses it: the
  facts are what tell two records apart, the source is what the operator
  weighs them by, and it belongs to the row rather than to the sentence. It
  renders as a badge beside the title.
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

  attr :control_class, :string,
    default: nil,
    doc: "sizes the control to its content — a date doesn't get a 900px box"

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
    <%!-- One slot order for every field — label row, control, hint, options —
          with an 8px beat inside the cluster. All bare text (label, hint,
          option row) sits on the text rail (pl-3), aligned with the text
          INSIDE the control; only boxes touch the margin edge. See
          docs/admin-design-language.md §1. --%>
    <div class={["space-y-2 rounded-lg border-l-4 bg-zinc-900 p-4", state_rail(@field)]}>
      <div class="flex items-baseline gap-2 pl-3">
        <.label>{@label}</.label>

        <%!-- Only when it says something the rail can't. Amber already means
            "look here"; "sources disagree" and "nothing proposed it" are
            different problems wanting different things from the operator, and
            a badge repeating "needs confirming" next to an amber rail is the
            same fact twice (§2). --%>
        <.badge
          :if={explained?(Field.state(@field))}
          color={elem(state_words(Field.state(@field)), 1)}
          class="text-xs"
        >
          {elem(state_words(Field.state(@field)), 0)}
        </.badge>

        <span :if={@field.approved && @field.source} class="text-xs text-zinc-400">
          from {source_words(@field.source)}
        </span>

        <span :if={@field.approved && is_nil(@field.source)} class="text-xs text-zinc-400">
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
        <%!-- pl-3 wrapper: an image is content, not a container — it sits on
            the text rail (design language §3). On the wrapper, so rows
            without a preview keep their input on the box edge. --%>
        <div :if={@preview && preview_src(@field.value, @embedded_src)} class="flex-none pl-3">
          <.image_with_size
            id={"#{@section}-#{@name}"}
            src={preview_src(@field.value, @embedded_src)}
            class="h-24 w-24 rounded-sm object-cover"
          />
        </div>

        <div class="min-w-0 flex-grow">
          <.inputs_for :let={decision} field={@form[@name]}>
            <.input
              :if={@type == "select"}
              field={decision[:value]}
              type="select"
              options={@options}
              class={@control_class}
            />
            <%!-- A date's precision is part of the date — one composite
                control, never a second decision box (§7). --%>
            <.date_with_format
              :if={@type == "date"}
              date_field={decision[:value]}
              format_field={decision[:format]}
            />
            <.input
              :if={@type not in ["select", "textarea", "date"]}
              field={decision[:value]}
              type={@type}
              placeholder={@placeholder}
              class={@control_class}
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
                  class="bg-zinc-800/50 absolute inset-0 hidden overflow-auto rounded-sm sm:block"
                >
                  <.markdown content={@field.value || ""} class="p-2" />
                </div>
              </div>
            </div>
          </.inputs_for>
        </div>
      </div>

      <p :if={@hint} class="pl-3 text-xs text-zinc-400">{@hint}</p>

      <%!-- The options row is a two-column grid — microlabel | chips — so a
            wrapping chip row stays in the chip column instead of falling
            back under the label, and every chip starts on one rail. --%>
      <%!-- Text chips align to the microlabel by baseline; image chips
          (cover previews) top-align instead — a baseline would put the
          label on the first image's bottom edge. --%>
      <div
        :if={@field.candidates != []}
        class={["grid-cols-[4rem_minmax(0,1fr)] grid gap-x-2 pl-3", (@preview && "items-start") || "items-baseline"]}
      >
        <.microlabel class={@preview && "pt-1.5"}>Proposed</.microlabel>

        <%!-- One line or a list, never a partial wrap — the hook measures
            whether every chip fits and commits to exactly one of the two. --%>
        <div
          id={"#{@section}-#{@name}-chips"}
          phx-hook="fit-or-stack"
          class="flex flex-wrap items-center gap-1.5"
        >
          <.proposal_chip
            :for={candidate <- @field.candidates}
            chosen={Field.chose?(@field, candidate)}
            event="choose-field"
            values={%{section: @section, field: @name, key: candidate.key}}
          >
            <%!-- Only the chosen chip is loud: its source tag fills lime. A
                  filled tag on every chip made the whole row heavy. --%>
            <span class={[
              "text-[10px] flex-none uppercase tracking-wide",
              Field.chose?(@field, candidate) && "bg-brand-dark rounded-sm px-1 text-zinc-900",
              !Field.chose?(@field, candidate) && "text-zinc-500"
            ]}>
              {candidate.label || source_words(candidate.source)}
            </span>
            <span :if={!@preview}>
              {truncate(candidate.value)}{precision_suffix(candidate)}
            </span>

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
                fields nobody filled in. Ghost, because it's the escape hatch,
                not a peer value. --%>
          <.proposal_chip
            :if={!@field.required}
            chosen={@field.approved && is_nil(@field.source)}
            event="waive-field"
            values={%{section: @section, field: @name}}
            ghost
          >
            None
          </.proposal_chip>
        </div>
      </div>
    </div>
    """
  end

  attr :credit, Credit, required: true
  attr :index, :integer, required: true
  attr :section, :string, required: true
  attr :identities, :list, required: true
  attr :verb, :string, required: true, doc: ~s(the visible label — "Written by")

  attr :identity_backing, :map,
    default: %{},
    doc: "identity id => the backing people's names, where they add something"

  attr :persons, :list, required: true, doc: "the PersonDecisions this credit references"

  attr :people, :list,
    default: [],
    doc: "the library's people, so a linked person's chip shows the library's own name and face"

  attr :count, :integer,
    default: 1,
    doc: "how many rows the list holds — the reorder arrows' ends"

  @doc """
  One credit, resolved to an identity.

  ## One control by default

  A credited name IS an identity. How many humans stand behind it is a fact
  about the *person* — not about this book — and no provider reports it, so
  asking on every import buried the two cases where the answer is interesting
  under dozens where it isn't. The person layer is a section of its own, and
  the credit carries a reference to it: names, faces, and a link.

  ## The name is editable

  A provider's spelling is a proposal like any other. Without a box to
  overrule it, "David Wong" could only be imported as a person called David
  Wong — the human is Jason Pargin, and that import is one author plus one
  differently-named person, which is now two edits rather than impossible.
  "This is a pen name" is the second of the two: it gives the human a name of
  their own and takes the operator to the card that now has a box for it.

  A link decision always targets an identity, never a Person. That is the
  generalized fix for the pen-name bug where matching found a Person and
  linked its first identity.
  """
  # Removed is a tombstone the operator can take back — a ghost row (dashed,
  # like every escape hatch) holding the name and a restore, out of the
  # decision queue. It renders instead of vanishing so removal is never a
  # one-way door.
  def credit_row(%{credit: %Credit{removed: true}} = assigns) do
    ~H"""
    <div
      class="rounded-lg border border-dashed border-zinc-700 p-4"
      data-role="removed-credit"
    >
      <div class="flex items-center justify-between gap-2 pl-3">
        <p class="min-w-0 truncate text-sm text-zinc-500">
          {@verb} <span class="line-through">{@credit.name}</span> (removed)
        </p>
        <button
          type="button"
          phx-click="restore-credit"
          phx-value-section={@section}
          phx-value-index={@index}
          class={action_classes(:zinc, "flex-none")}
        >
          Restore
        </button>
      </div>
    </div>
    """
  end

  def credit_row(assigns) do
    assigns = assign(assigns, :faces, Enum.map(assigns.persons, &person_face(&1, assigns.people)))

    ~H"""
    <%!-- A decision block, so it wears the state rail like every other one —
        the rail is the ONLY settledness encoding (design language §2); the
        check icon it used to grow shifted the title sideways on approval. --%>
    <div class={["space-y-2 rounded-lg border-l-4 bg-zinc-900 p-4", state_rail(@credit)]}>
      <div class="flex items-center justify-between gap-2 pl-3">
        <div class="flex min-w-0 items-baseline gap-2">
          <.label>{@verb}</.label>

          <.badge
            :if={explained?(Credit.state(@credit))}
            color={elem(state_words(Credit.state(@credit)), 1)}
            class="text-xs"
          >
            {elem(state_words(Credit.state(@credit)), 0)}
          </.badge>

          <span :if={@credit.source} class="text-xs text-zinc-400">
            from {source_words(@credit.source)}
          </span>
        </div>

        <div class="flex flex-none items-center gap-2">
          <.card_move_buttons event="move-credit" section={@section} index={@index} count={@count} />

          <button
            :if={!@credit.approved}
            type="button"
            phx-click="approve-credit"
            phx-value-section={@section}
            phx-value-index={@index}
            phx-value-approved="true"
            class={action_classes()}
          >
            Confirm
          </button>

          <button
            type="button"
            phx-click="remove-credit"
            phx-value-section={@section}
            phx-value-index={@index}
            title="This audiobook isn't by them"
          >
            <.icon name="fa-xmark" class="h-4 w-4 cursor-pointer hover:text-red-600" />
          </button>
        </div>
      </div>

      <%!-- The people ride beside the box rather than under it. A credit is
            one line of meaning — this name, these humans — and a full-cast
            recording is a run of these rows, where a second line each is what
            turns the section into a wall. --%>
      <div class="flex flex-wrap items-center gap-2">
        <form
          id={"credit-#{@section}-#{@index}-identity"}
          phx-change="credit-change"
          class="min-w-48 flex flex-grow flex-wrap items-baseline gap-2"
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
            class="text-xs text-zinc-400"
            data-role="identity-backing"
          >
            {@identity_backing[@credit.identity_id]}
          </span>
        </form>

        <%!-- A reference, not the person. The human lives once, in the People
              section, because one human is one record — rendering them inside
              every credit that named them is what made an author who reads
              their own book appear twice, with a sentence apologising for it.
              What a credit needs is enough to recognise who it means and a way
              to get there. --%>
        <div
          :if={@credit.mode == :create and @persons != []}
          class="flex flex-none flex-wrap gap-2"
          data-role="credit-people"
        >
          <.link
            :for={face <- Enum.take(@faces, person_chips())}
            href={"#person-#{face.key}"}
            class="bg-white/5 flex items-center gap-2 rounded-full py-1 pr-3 pl-1 text-xs text-zinc-300 hover:bg-white/10"
          >
            <img
              :if={face.src}
              src={face.src}
              class="h-6 w-6 flex-none rounded-full object-cover"
              alt=""
            />
            <span :if={!face.src} class="h-6 w-6 flex-none rounded-full bg-zinc-800" />
            {face.name}
          </.link>

          <%!-- One credit standing for a dozen humans would push the row into
                a paragraph of faces. The rest are a click away in the section
                that lists every one of them. --%>
          <.link
            :if={length(@faces) > person_chips()}
            href="#people"
            title={Enum.map_join(Enum.drop(@faces, person_chips()), ", ", & &1.name)}
            class="bg-white/10 flex items-center rounded-full px-3 py-1 text-xs tabular-nums text-zinc-300 hover:bg-white/20"
          >
            +{length(@faces) - person_chips()}
          </.link>
        </div>
      </div>

      <%!-- The way back after a rename or a clear — the same chip the scalar
            fields have always had. Only speaks while the box disagrees with
            the evidence; a linked identity has the library's own name. --%>
      <div
        :if={
          @credit.mode == :create && @credit.proposed_name &&
            @credit.proposed_name != @credit.name
        }
        class="grid-cols-[4rem_minmax(0,1fr)] grid items-baseline gap-x-2 pl-3"
      >
        <.microlabel>Proposed</.microlabel>
        <div class="flex flex-wrap items-center gap-1.5">
          <.proposal_chip
            chosen={false}
            event="reset-credit-name"
            values={%{section: @section, index: @index}}
            title="go back to what the records proposed"
          >
            <span class="text-[10px] flex-none uppercase tracking-wide text-zinc-500">
              {source_words(@credit.source)}
            </span>
            {@credit.proposed_name}
          </.proposal_chip>
        </div>
      </div>
    </div>
    """
  end

  attr :person, PersonDecision, required: true
  attr :group, :map, required: true, doc: "the credit that introduces this human"
  attr :person_index, :integer, required: true
  attr :removable, :boolean, default: false, doc: "only a pen name's extra people can be removed"
  attr :searching, :boolean, default: false
  attr :photos_expanded, :boolean, default: false
  attr :records, :list, default: []
  attr :locals, :list, default: [], doc: "people the library already has by this name"
  attr :outcomes, :list, default: []
  attr :appears, :list, default: []
  attr :people, :list, default: [], doc: "the library's people, for the typeahead"

  attr :query_name, :string,
    default: nil,
    doc: "the name these records were searched for; falls back to the person's own"

  @doc """
  One human this import will create, as a decision card of their own.

  The card is where a person's own questions live — what they are called, which
  face, which biography — separately from the *credit*, which asks a different
  question: which identity does this book credit. They were one control for a
  long time, which is why an author reading their own book rendered twice.

  ## The name box is the exception, not the furniture

  A credited name is the human's name in almost every import, so the card
  states it and offers nothing to type. The box appears when the name is
  genuinely the person's own — the operator said the credit is a pen name, or
  the credit stands for several humans, neither of whom it names. That is also
  what "This is a pen name" was missing: with a name box on every card in
  every state, the control had no visible effect at all.

  The events still address the credit that introduces them (`section`,
  `index`, `person_index`), because "remove this person" means removing them
  from that credit — the person exists only as long as a credit names them.
  """
  def person_card(assigns) do
    assigns =
      assign(assigns,
        own_name: assigns.person.own_name or not Credit.simple?(assigns.group.credit),
        linked: linked_person(assigns.people, assigns.person),
        # A linked person is called what the library calls them, here as well
        # as on the credit chip — the staged name is a leftover of finding
        # them, not their name.
        words: person_words(assigns.person, linked_person(assigns.people, assigns.person))
      )

    ~H"""
    <div
      id={"person-#{@person.key}"}
      class={["relative space-y-3 rounded-lg border-l-4 bg-zinc-900 p-4", state_rail(@person)]}
      data-role="person-card"
    >
      <%!-- A provider round-trip is the same kind of event as a matching job,
            and gets the same answer: the card is not yours while it runs. A
            button changing its own label to "Searching…" was the whole
            indication, in a fold that could close over it. --%>
      <%!-- Named by the QUERY, like the work and recording scrims: a search
            for a name other than this person's own said "Looking for
            <the person>…" while looking for somebody else entirely. --%>
      <.busy_overlay busy={@searching} label={"Looking for #{@query_name || @words}…"} />

      <div class="space-y-3" inert={@searching}>
        <%!-- Titled by the CREDIT, which is the one name on this card that
              doesn't move: the box below is the human's name, and a header
              that followed it re-titled the card letter by letter while the
              operator typed the very thing the card is about. --%>
        <div class="flex items-baseline justify-between gap-2 pl-3">
          <div class="flex min-w-0 items-baseline gap-2">
            <.label>{card_words(@group.credit, @words)}</.label>

            <%!-- Where they are credited is a fact about this card, so it
                  wears the status costume beside the title rather than a
                  sentence under it. --%>
            <.badge :if={@appears != []} color={:gray} class="text-xs">
              {credited_words(@appears)}
            </.badge>
          </div>

          <button
            :if={@removable}
            type="button"
            phx-click="remove-person"
            phx-value-section={@group.section}
            phx-value-index={@group.index}
            phx-value-person={@person_index}
            title="not one of the people behind this name"
          >
            <.icon name="fa-xmark" class="h-3 w-3 cursor-pointer hover:text-red-600" />
          </button>
        </div>

        <%!-- One human on two credits is the ordinary reason a name appears
              twice, so it is the default, and the badge above already says
              which two. What is left is the escape hatch for the other case,
              asked here because the card exists once per person. --%>
        <p
          :if={length(Enum.uniq_by(@appears, & &1.kind)) > 1}
          class="pl-3 text-xs text-zinc-400"
        >
          <button
            type="button"
            phx-click="split-person"
            phx-value-section={@group.section}
            phx-value-index={@group.index}
            phx-value-person={@person_index}
            class="underline"
          >
            Not the same person?
          </button>
        </p>

        <%!-- The 99-in-100 case: the credit names the human, the title says so,
              and the card asks nothing. The link is the whole line — saying
              "named by the credit" under a card titled by the credit was the
              same fact twice. --%>
        <p :if={@person.mode == :create and !@own_name} class="pl-3 text-xs text-zinc-400">
          <button
            type="button"
            phx-click="separate-name"
            phx-value-section={@group.section}
            phx-value-index={@group.index}
            class="underline"
          >
            {reveal_words(@group.kind)}
          </button>
        </p>

        <%!-- The exception, revealed: a provider's spelling is a proposal, and
              without a box to overrule it "David Wong" could only be imported
              as a person called David Wong when the human is Jason Pargin. The
              typeahead is also how they become somebody already in the
              library. --%>
        <div :if={@person.mode == :create and @own_name} class="space-y-1">
          <p class="pl-3 text-xs text-zinc-400">{alias_words(@group.kind)}</p>

          <form id={"person-#{@person.key}-identity"} phx-change="person-change">
            <input type="hidden" name="key" value={@person.key} />

            <.live_component
              module={EntityResolver}
              id={"person-#{@person.key}-resolver"}
              name="person_id"
              text_name="name"
              options={@people}
              value={nil}
              text={Field.value(@person.name) || ""}
              placeholder="the person's real name"
              class={input_classes("w-full")}
            />
          </form>

          <%!-- Both escape hatches from the same state, on the rail under the
                box they belong to. A shared pen name is the composite-author
                case and it is asked here rather than on the credit, where it
                changed a card the operator couldn't see. Narrators stay
                one-to-one with a person by design. --%>
          <div class="flex flex-wrap items-baseline gap-x-4 pl-3 text-xs text-zinc-400">
            <span :if={@group.section == "work"}>
              Is this pen name more than one person?
              <button
                type="button"
                phx-click="add-person"
                phx-value-section={@group.section}
                phx-value-index={@group.index}
                class="underline"
              >
                Add a person
              </button>
            </span>

            <%!-- Every way in needs a way out: the reveal used to be a fold
                  that could not be folded back. --%>
            <button
              :if={Credit.simple?(@group.credit)}
              type="button"
              phx-click="use-credited-name"
              phx-value-key={@person.key}
              class="underline"
            >
              No, {@group.credit.name} is their name
            </button>
          </div>
        </div>

        <%!-- A different KIND of question from the provider records below, and
              the same shape the work level gives it: those describe a human,
              this one IS one, and choosing them creates nobody. Matching
              collects them whenever a credited name is already in the library
              — which is exactly the author who turns up narrating. --%>
        <div :if={@locals != [] or @person.mode == :link} class="space-y-2">
          <p class="pl-3 text-xs text-zinc-400">
            {local_people_words(@person, @locals, @group.kind)}
          </p>

          <.local_person_row
            :for={local <- @locals}
            local={local}
            person_key={@person.key}
            chosen={@person.mode == :link and @person.person_id == local["id"]}
          />

          <%!-- Linked to somebody the name search never offered (the typeahead
                above), so the row is built from the library instead. --%>
          <.local_person_row
            :if={@person.mode == :link and not Enum.any?(@locals, &(&1["id"] == @person.person_id))}
            local={@linked}
            person_key={@person.key}
            chosen={true}
          />
        </div>

        <.person_curation
          person={@person}
          section={@group.section}
          index={@group.index}
          person_index={@person_index}
          kind={@group.kind}
          appears={@appears}
          searching={@searching}
          expanded={@photos_expanded}
          records={@records}
          outcomes={@outcomes}
          query_name={@query_name}
        />
      </div>
    </div>
    """
  end

  defp person_words(_person, %{"name" => name}), do: name
  defp person_words(person, nil), do: Field.value(person.name) || "Unnamed person"

  # The credited name, which is what this card is a card *about*. Falls back
  # to the human's own name only when the credit has none — a cleared credit
  # box mid-retype, where a blank title would name nothing at all.
  defp card_words(%Credit{name: name}, words) when is_binary(name) do
    if String.trim(name) == "", do: words, else: name
  end

  defp card_words(_credit, words), do: words

  defp reveal_words(:narrator), do: "This is a stage name"
  defp reveal_words(_author), do: "This is a pen name"

  defp alias_words(:narrator), do: "A stage name of"
  defp alias_words(_author), do: "A pen name of"

  # The library's own row for a person linked from the typeahead rather than
  # from the rows below — enough to say who, and to take it back.
  defp linked_person(people, %PersonDecision{mode: :link, person_id: id}) do
    case Enum.find(people, &(&1.id == id)) do
      nil -> %{"id" => id, "name" => "Somebody in your library"}
      person -> %{"id" => person.id, "name" => person.label, "image" => person.image}
    end
  end

  defp linked_person(_people, _person), do: nil

  @doc """
  What to show for a person: the library's own name and face where this
  decision links to one, the staged fields where it will create one.

  A linked decision keeps whatever was typed on the way to finding them, by
  design — linking must not overwrite staged curation, because unlinking has
  to give it back. But rendering it is wrong: type "j", pick J.K. Rowling
  from the typeahead, and the credit chip read "j" beside the portrait of
  whichever candidate the half-typed name had turned up.

  The src is resolved here rather than by the caller because the two cases
  need different handling — a library thumbnail is a local path served as-is,
  a staged image may be a remote provider URL that has to go through the
  proxy.
  """
  def person_face(person, people) do
    case linked_person(people, person) do
      nil ->
        %{
          key: person.key,
          name: Field.value(person.name) || "unnamed",
          src: preview_src(Field.value(person.image), nil)
        }

      linked ->
        %{key: person.key, name: linked["name"], src: linked["image"]}
    end
  end

  # Linking is an answer to "who is this", and a pen name is an answer to
  # "whose name is on the book" — the second doesn't stop being true because
  # the first was answered from the library. Saying so generically here threw
  # away the more specific thing the card had been saying one state earlier.
  defp local_people_words(%PersonDecision{mode: :link, own_name: true}, _locals, kind),
    do: alias_words(kind)

  defp local_people_words(%PersonDecision{mode: :link}, _locals, _kind),
    do: "This import will use the person you already have."

  defp local_people_words(_person, [_one], _kind),
    do: "Somebody by this name is already in your library."

  defp local_people_words(_person, locals, _kind),
    do: "#{length(locals)} people by this name are already in your library."

  attr :local, :map, required: true
  attr :person_key, :string, required: true
  attr :chosen, :boolean, required: true

  @doc """
  A person the library already has, offered instead of creating another.

  The same well the local-book row is, because it is the same question one
  level down: reusing a human is the outcome worth having, and the form's job
  is to make it one click rather than a duplicate nobody notices until two
  Andy Weirs are sitting in the people list.
  """
  def local_person_row(assigns) do
    ~H"""
    <div
      class={[
        "flex items-center gap-3 rounded-md p-3",
        @chosen && "bg-brand-dark/10 ring-brand-dark/50 ring-2 ring-inset",
        !@chosen && "bg-zinc-800/60"
      ]}
      data-role="local-person"
      data-linked={@chosen && "true"}
    >
      <div class="min-w-0 flex-grow">
        <p class="truncate text-sm font-semibold">{@local["name"]}</p>
        <p :if={local_facts(@local)} class="truncate text-xs text-zinc-400">{local_facts(@local)}</p>
      </div>

      <button
        :if={!@chosen}
        type="button"
        phx-click="link-person"
        phx-value-key={@person_key}
        phx-value-id={@local["id"]}
        class={action_classes(:zinc, "flex-none")}
      >
        Yes, it's them
      </button>

      <button
        :if={@chosen}
        type="button"
        phx-click="unlink-person"
        phx-value-key={@person_key}
        class={action_classes(:zinc, "flex-none")}
      >
        No, a new person
      </button>
    </div>
    """
  end

  # What the library already knows about them, which is the whole reason to
  # reuse the record rather than make a second one.
  defp local_facts(local) do
    [
      local["has_image"] && "has a photo",
      local["has_description"] && "has a biography"
    ]
    |> Enum.filter(& &1)
    |> case do
      [] -> nil
      facts -> Enum.join(facts, " · ")
    end
  end

  @doc """
  Where this human is credited, as the badge beside the card's title.

  The card is away from the credits, so it has to say what it belongs to.
  A badge rather than a sentence because that is what it is: a fact about the
  card, stated once, in the costume every other status fact wears. The
  interesting half — that two credits mean one person rather than two of a
  name — is a line of its own, since it comes with a control.
  """
  def credited_words(appears) do
    appears
    |> Enum.map(& &1.kind)
    |> Enum.uniq()
    |> Enum.map(fn
      :author -> "author"
      :narrator -> "narrator"
      other -> to_string(other)
    end)
    |> case do
      [] -> "Credited nowhere"
      kinds -> "Credited as #{Enum.join(kinds, " and ")}"
    end
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

  attr :query_name, :string,
    default: nil,
    doc: "the name these records were searched for; falls back to the person's own"

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
      <%!-- pl-3: an image is content, not a container — it sits on the text
          rail like the words around it (design language §3). --%>
      <div class="flex items-center gap-2 pl-3">
        <.image_with_size
          :if={@image}
          id={"person-#{@at}-photo"}
          src={proxied_remote_image_url(@image)}
          class="h-12 w-12 flex-none rounded-full object-cover object-top"
        />

        <span
          :if={is_nil(@image)}
          class="h-12 w-12 flex-none rounded-full border border-dashed border-zinc-700"
        />
      </div>

      <%!-- The same three parts in the same order as the work and recording
            levels, and now with the same name on them: the query, who
            answered, and what they said. The person level used to carry no
            label at all and its search hid in a fold under its own results. --%>
      <.microlabel class="block pl-3">Provider records</.microlabel>

      <.person_research_form
        at={@at}
        person_key={@person.key}
        name={@query_name || Field.value(@person.name)}
        running={@searching}
      />

      <.provider_outcomes_row outcomes={@outcomes} retryable={false} />

      <%!-- Nothing found is a normal outcome, not a failure — plenty of
            narrators are in no database at all — but it should say so rather
            than looking like an empty grid nobody filled in. --%>
      <p :if={@person.doubt == :low_confidence} class="pl-3 text-xs text-zinc-400">
        {@person.doubt_detail}
      </p>

      <%!-- Folded on the same threshold as the work and recording levels, and
            for the same reason: a re-search under a new name leaves the old
            name's records scored against a question nobody is asking any
            more, and eight rows of equal weight is how the wrong human stays
            in the running. A ticked record is never folded. --%>
      <.record_list records={@records} used={&PersonDecision.uses?(@person, &1)}>
        <:row :let={record}>
          <.record_row
            record={record}
            event="toggle-person-source"
            person_key={@person.key}
            used={PersonDecision.uses?(@person, record)}
          />
        </:row>
      </.record_list>

      <%!-- The same answer the other two levels have. A person the matcher
            doubted — it found humans of roughly this name and believed none
            of them — stays outstanding until somebody says so, and this is
            what says so. It costs nothing but the photo and the biography:
            a name is all it takes to create a person. --%>
      <div :if={@records != []} class="flex flex-wrap items-center gap-2 pt-1">
        <button
          type="button"
          phx-click="uncatalogued-person"
          phx-value-key={@person.key}
          data-role="none-of-these"
          class={[
            "px-[11px] rounded-md border py-1 text-xs",
            PersonDecision.uncatalogued?(@person) &&
              "bg-brand-dark/15 ring-brand-dark/50 border-transparent ring-2 ring-inset",
            !PersonDecision.uncatalogued?(@person) &&
              "border-dashed border-zinc-600 text-zinc-400 hover:border-zinc-500 hover:text-zinc-200"
          ]}
        >
          None of these
        </button>
      </div>

      <div :if={@photos != []} class="grid-cols-[4rem_minmax(0,1fr)] grid items-start gap-x-2 pl-3">
        <.microlabel class="pt-1">Photos</.microlabel>

        <div class="flex flex-wrap items-center gap-2">
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
            class="text-xs text-zinc-400 underline"
          >
            {if @expanded, do: "show fewer", else: "show all #{length(@photos)} photos"}
          </button>

          <button
            :if={@image}
            type="button"
            phx-click="waive-person-field"
            phx-value-key={@person.key}
            phx-value-field="image"
            class="self-center rounded-sm border border-dashed border-zinc-600 px-2 py-1 text-xs text-zinc-400 hover:border-zinc-500 hover:text-zinc-200"
          >
            no photo
          </button>
        </div>
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
              class="bg-zinc-800/50 absolute inset-0 hidden overflow-auto rounded-sm sm:block"
            >
              <.markdown content={@description || ""} class="p-2" />
            </div>
          </div>
        </div>

        <div :if={@bios != []} class="grid-cols-[4rem_minmax(0,1fr)] grid items-baseline gap-x-2 pl-3">
          <.microlabel>Proposed</.microlabel>

          <div
            id={"person-bio-#{@at}-chips"}
            phx-hook="fit-or-stack"
            class="flex flex-wrap items-center gap-1.5"
          >
            <.proposal_chip
              :for={bio <- @bios}
              chosen={Field.chose?(@person.description, bio)}
              event="pick-person-bio"
              values={%{"key" => @person.key, "candidate" => bio.key}}
              title={bio.value}
            >
              <span class={[
                "text-[10px] flex-none uppercase tracking-wide",
                Field.chose?(@person.description, bio) && "bg-brand-dark rounded-sm px-1 text-zinc-900",
                !Field.chose?(@person.description, bio) && "text-zinc-400"
              ]}>
                {bio.label}
              </span>
              <span class="line-clamp-1">{truncate(bio.value)}</span>
            </.proposal_chip>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp photo_preview, do: @photo_preview

  # How many faces a credit shows before it starts counting instead. Four is
  # a composite author plus room to spare; a credit standing for more than
  # that is a list, and the People section is where lists live.
  @person_chips 4

  defp person_chips, do: @person_chips

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

  attr :event, :string, required: true
  attr :section, :string, default: nil
  attr :index, :integer, required: true
  attr :count, :integer, required: true

  @doc """
  Compact reorder arrows for a decision card's header action group — the
  list-row `move_buttons` costume shrunk to icon size, because a card header
  carries its verbs as icons (the ✕ beside these). List order is billing
  order, so the cards need a way to say who comes first.
  """
  def card_move_buttons(assigns) do
    ~H"""
    <div :if={@count > 1} class="flex flex-none items-center gap-1" data-role="move-buttons">
      <button
        type="button"
        phx-click={@event}
        phx-value-section={@section}
        phx-value-index={@index}
        phx-value-direction="up"
        disabled={@index == 0}
        class="disabled:opacity-25"
        title="Move up"
      >
        <.icon name="fa-chevron-up" class="h-3.5 w-3.5 cursor-pointer text-current hover:text-zinc-100" />
      </button>
      <button
        type="button"
        phx-click={@event}
        phx-value-section={@section}
        phx-value-index={@index}
        phx-value-direction="down"
        disabled={@index == @count - 1}
        class="disabled:opacity-25"
        title="Move down"
      >
        <.icon name="fa-chevron-down" class="h-3.5 w-3.5 cursor-pointer text-current hover:text-zinc-100" />
      </button>
    </div>
    """
  end

  attr :chosen, :boolean, required: true
  attr :event, :string, required: true
  attr :values, :map, default: %{}
  attr :title, :string, default: nil
  attr :shape, :string, default: "text"
  attr :ghost, :boolean, default: false, doc: ~s(escape hatches like "None" — dashed and quiet)
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
        "max-w-full rounded-md text-left text-xs",
        @shape == "circle" && "rounded-full p-0.5",
        @shape != "circle" && "inline-flex items-center gap-1.5 px-2 py-1",
        @chosen && "bg-brand-dark/15 ring-brand-dark/50 ring-2 ring-inset",
        !@chosen && !@ghost && "bg-zinc-800 text-zinc-300 hover:bg-zinc-700 hover:text-zinc-100",
        !@chosen && @ghost && "border border-dashed border-zinc-600 text-zinc-400 hover:border-zinc-500 hover:text-zinc-200"
      ]}
    >
      <%!-- The chosen chip is the single most important state on the form, and
            a 1px border-hue change was nearly invisible — so it says so three
            ways: border, tint, and a check. --%>
      <.icon
        :if={@chosen && @shape != "circle"}
        name="fa-check"
        class="text-brand-dark h-3 w-3 flex-none"
      />
      {render_slot(@inner_block)}
    </button>
    """
  end

  defp chip_values(values),
    do: Map.new(values, fn {key, value} -> {"phx-value-#{key}", value} end)

  # "2015 (year only)" — a date proposal's precision is part of its value.
  defp precision_suffix(%{format: format}) when format in ["year", "year_month"],
    do: " (#{precision_words(format)})"

  defp precision_suffix(_candidate), do: nil

  defp precision_words("year"), do: "year only"
  defp precision_words("year_month"), do: "year & month"

  attr :link, SeriesLink, required: true
  attr :index, :integer, required: true
  attr :options, :list, required: true

  attr :count, :integer,
    default: 1,
    doc: "how many rows the list holds — the reorder arrows' ends"

  @doc """
  One series membership, with its number.

  Each series is its own decision, which is what fixes the standing complaint
  that the import forms take all series or none. The number is never
  defaulted — a series proposal with no number stays outstanding, because
  inventing "book 1" writes confident nonsense into a curated field.
  """
  # The same ghost as a removed credit: dashed, named, restorable.
  def series_row(%{link: %SeriesLink{removed: true}} = assigns) do
    ~H"""
    <div
      class="rounded-lg border border-dashed border-zinc-700 p-4"
      data-role="removed-series"
    >
      <div class="flex items-center justify-between gap-2 pl-3">
        <p class="min-w-0 truncate text-sm text-zinc-500">
          In series <span class="line-through">{@link.name}</span> (removed)
        </p>
        <button
          type="button"
          phx-click="restore-series"
          phx-value-index={@index}
          class={action_classes(:zinc, "flex-none")}
        >
          Restore
        </button>
      </div>
    </div>
    """
  end

  def series_row(assigns) do
    ~H"""
    <%!-- The same anatomy as every other decision block: railed header row
        with the state on the block's left rail (no extra check icon — the
        rail is the only settledness encoding, §2), controls below with
        their labels above them. --%>
    <div
      class={["space-y-2 rounded-lg border-l-4 bg-zinc-900 p-4", state_rail(@link)]}
      data-role="series-link"
    >
      <div class="flex items-center justify-between gap-2 pl-3">
        <div class="flex min-w-0 items-baseline gap-2">
          <.label>In series</.label>

          <%!-- Only where it says something the rail can't (§2): "needs
                confirming" beside an amber rail is the same fact twice. --%>
          <.badge
            :if={explained?(SeriesLink.state(@link))}
            color={elem(state_words(SeriesLink.state(@link)), 1)}
            class="text-xs"
          >
            {elem(state_words(SeriesLink.state(@link)), 0)}
          </.badge>

          <%!-- Every other decision block says where its answer came from; a
              series membership is a proposal like any other and was the one
              block that didn't, so a settled row said nothing at all. --%>
          <span :if={@link.source} class="text-xs text-zinc-400">
            from {source_words(@link.source)}
          </span>
        </div>

        <div class="flex flex-none items-center gap-2">
          <.card_move_buttons event="move-series" index={@index} count={@count} />

          <button
            :if={!@link.approved and @link.number}
            type="button"
            phx-click="approve-series"
            phx-value-index={@index}
            phx-value-approved="true"
            class={action_classes()}
          >
            Confirm
          </button>

          <button
            type="button"
            phx-click="remove-series"
            phx-value-index={@index}
            title="Not in this series"
          >
            <.icon name="fa-xmark" class="h-4 w-4 cursor-pointer hover:text-red-600" />
          </button>
        </div>
      </div>

      <%!-- Boxes on one line align by their boxes, not a baseline (§3), and
          the number wears no label: the book form has always spelled this
          field with a placeholder alone, and a label over one box of two
          made the row tall and the two controls' tops disagree. --%>
      <div class="flex flex-wrap items-center gap-x-3 gap-y-2">
        <form
          id={"series-#{@index}-link"}
          phx-change="link-series"
          class="min-w-48 max-w-md flex-grow"
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

        <form id={"series-#{@index}-number"} phx-change="set-series-number" class="flex-none">
          <input type="hidden" name="index" value={@index} />
          <input
            type="text"
            name="number"
            value={@link.number}
            placeholder="no."
            class={input_classes("w-16")}
          />
        </form>
      </div>

      <%!-- Same restore chip as a credit's name: the evidence's spelling
            stays reachable after a rename or a clear. --%>
      <div
        :if={@link.mode == :create && @link.proposed_name && @link.proposed_name != @link.name}
        class="grid-cols-[4rem_minmax(0,1fr)] grid items-baseline gap-x-2 pl-3"
      >
        <.microlabel>Proposed</.microlabel>
        <div class="flex flex-wrap items-center gap-1.5">
          <.proposal_chip
            chosen={false}
            event="reset-series-name"
            values={%{index: @index}}
            title="go back to what the records proposed"
          >
            <span class="text-[10px] flex-none uppercase tracking-wide text-zinc-500">
              {source_words(@link.source)}
            </span>
            {@link.proposed_name}
          </.proposal_chip>
        </div>
      </div>
    </div>
    """
  end

  attr :link, GroupLink, required: true
  attr :options, :list, required: true

  @doc """
  The recording's place in a part set — which group it joins or creates, and
  its part number within it. The series row's mirror, one level down and
  singular: a recording is in at most one set.

  The part number is never defaulted, same doctrine as the series number —
  "part of this set, position unknown" is a question, not an answer.
  """
  # The same ghost as a removed series: dashed, named, restorable.
  def group_row(%{link: %GroupLink{removed: true}} = assigns) do
    ~H"""
    <div
      class="rounded-lg border border-dashed border-zinc-700 p-4"
      data-role="removed-group"
    >
      <div class="flex items-center justify-between gap-2 pl-3">
        <p class="min-w-0 truncate text-sm text-zinc-500">
          Part of <span class="line-through">{@link.name}</span> (removed)
        </p>
        <button
          type="button"
          phx-click="restore-group"
          class={action_classes(:zinc, "flex-none")}
        >
          Restore
        </button>
      </div>
    </div>
    """
  end

  def group_row(assigns) do
    ~H"""
    <div
      class={["space-y-2 rounded-lg border-l-4 bg-zinc-900 p-4", state_rail(@link)]}
      data-role="group-link"
    >
      <div class="flex items-center justify-between gap-2 pl-3">
        <div class="flex min-w-0 items-baseline gap-2">
          <.label>Part of a set</.label>

          <.badge
            :if={explained?(GroupLink.state(@link))}
            color={elem(state_words(GroupLink.state(@link)), 1)}
            class="text-xs"
          >
            {elem(state_words(GroupLink.state(@link)), 0)}
          </.badge>

          <%!-- The series row's mirror in this too. --%>
          <span :if={@link.source} class="text-xs text-zinc-400">
            from {source_words(@link.source)}
          </span>
        </div>

        <div class="flex flex-none items-center gap-2">
          <button
            :if={!@link.approved and @link.part_number}
            type="button"
            phx-click="approve-group"
            phx-value-approved="true"
            class={action_classes()}
          >
            Confirm
          </button>

          <button type="button" phx-click="remove-group" title="Not part of a set">
            <.icon name="fa-xmark" class="h-4 w-4 cursor-pointer hover:text-red-600" />
          </button>
        </div>
      </div>

      <%!-- The cross-item case this row exists for: an earlier part already
          created the set, and joining it is what keeps one work from
          growing a second, parallel group. --%>
      <p
        :if={@link.mode == :link and not @link.curated and not GroupLink.resolved?(@link)}
        class="pl-3 text-sm text-zinc-400"
        data-role="group-sibling-callout"
      >
        This book already has a set. Is this another part of it?
      </p>

      <%!-- Reads as a sentence across the row — "<set> no. 1 of 3" — with the
          same label-free number box the series row and the book form use. --%>
      <div class="flex flex-wrap items-center gap-x-3 gap-y-2">
        <form id="group-link" phx-change="link-group" class="min-w-48 max-w-md flex-grow">
          <.live_component
            module={EntityResolver}
            id="group-resolver"
            name="recording_group_id"
            text_name="name"
            options={@options}
            value={if @link.mode == :link, do: @link.recording_group_id}
            text={@link.name || ""}
            placeholder="set name"
            class={input_classes("w-full")}
          />
        </form>

        <form id="group-part" phx-change="set-group-part" class="flex-none">
          <input
            type="number"
            min="1"
            name="part_number"
            value={@link.part_number}
            placeholder="no."
            class={input_classes("w-16")}
            data-role="part-number"
          />
        </form>

        <%!-- On :link the total is the linked group's fact, shown not asked;
            on :create it's the new set's birth certificate. --%>
        <p :if={@link.mode == :create} class="text-sm text-zinc-400">of</p>

        <form :if={@link.mode == :create} id="group-total" phx-change="set-group-total" class="flex-none">
          <input
            type="number"
            min="1"
            name="parts_total"
            value={@link.parts_total}
            placeholder="total"
            class={input_classes("w-16")}
            data-role="parts-total"
          />
        </form>

        <p :if={@link.mode == :link and @link.parts_total} class="text-sm text-zinc-400">
          of {@link.parts_total}
        </p>
      </div>

      <%!-- Same restore chip as a series' name: the evidence's spelling
            stays reachable after a rename or a clear. --%>
      <div
        :if={@link.mode == :create && @link.proposed_name && @link.proposed_name != @link.name}
        class="grid-cols-[4rem_minmax(0,1fr)] grid items-baseline gap-x-2 pl-3"
      >
        <.microlabel>Proposed</.microlabel>
        <div class="flex flex-wrap items-center gap-1.5">
          <.proposal_chip
            chosen={false}
            event="reset-group-name"
            values={%{}}
            title="go back to what the evidence proposed"
          >
            <span class="text-[10px] flex-none uppercase tracking-wide text-zinc-500">
              {source_words(@link.source)}
            </span>
            {@link.proposed_name}
          </.proposal_chip>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  The block's left rail — the one thing that encodes settledness (§2).

  The tiers exist because settled-versus-waiting threw away the question the
  operator actually asks of a machine-matched import: has anyone looked at
  this yet. A 4px rail renders crisp at any DPI where a tinted hairline goes
  mushy.

  `:uncatalogued` shares amber with `:waiting`: both want a look, and the
  rail says *how settled*, not *what to do about it* — the badge beside it
  is where the two part company.
  """
  def state_rail(%{__struct__: _} = decision), do: state_rail(Tier.of(decision))
  def state_rail(:blocked), do: "border-red-400/70"
  def state_rail(:waiting), do: "border-amber-400/70"
  def state_rail(:uncatalogued), do: "border-amber-400/70"
  def state_rail(:unreviewed), do: "border-blue-400/70"
  def state_rail(:reviewed), do: "border-brand-dark/60"

  @doc """
  Whether this state is worth a badge beside the rail.

  The rail already says settled-or-not; a badge earns its place only when it
  names a *reason* the colour can't — which values disagree, that nothing
  proposed one at all, or which half of a membership is still blank.
  """
  def explained?(state), do: state in [:missing, :unnumbered, :ambiguous, :stale]

  @doc """
  A decision's state as words and a colour.

  `:missing` and `:ambiguous` read differently on purpose — one needs a value
  from somewhere, the other needs a choice between values already in hand.
  Calling both "unresolved" throws that distinction away.
  """
  def state_words(:approved), do: {"settled", :brand}
  def state_words(:missing), do: {"nothing proposed it", :red}
  # What is missing is the number, and a row that says "nothing proposed it"
  # next to "from rreading-glasses" contradicts itself in two words.
  def state_words(:unnumbered), do: {"needs a number", :red}
  def state_words(:ambiguous), do: {"sources disagree", :yellow}
  def state_words(:unconfirmed), do: {"needs confirming", :yellow}
  def state_words(:stale), do: {"files changed", :red}
  def state_words(_other), do: {"needs confirming", :yellow}

  @doc """
  A tier as words and a colour, for surfaces with no room for a rail.

  A queue row is one line: it has nowhere to put a 4px edge per level, so it
  says the same states in words. Same vocabulary as the form's rail, or the
  two drift — which is exactly what happened when the queue had its own.

  `:uncatalogued` is the one tier the words say more than the rail does: it
  shares amber with `:waiting` because both want a look, but "nothing found"
  and "needs you" ask for completely different things, and the queue printing
  "matched" over an empty candidate list is what made the distinction worth
  having.
  """
  def tier_words(:blocked), do: {"blocked", :red}
  def tier_words(:waiting), do: {"needs you", :yellow}
  def tier_words(:uncatalogued), do: {"nothing found", :yellow}
  def tier_words(:unreviewed), do: {"matched", :blue}
  def tier_words(:reviewed), do: {"reviewed", :brand}

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

  # A group proposal used to seed its own words for these two, back when
  # nothing rendered a group's provenance and "from name" was never seen.
  # Drafts stored before that still carry them.
  def source_words("name"), do: "the release name"
  def source_words("library"), do: "the library"

  def source_words("provider:" <> id = source) do
    case Ambry.Metadata.Registry.fetch(id) do
      {:ok, entry} -> entry.display_name
      {:error, :unknown_provider} -> source
    end
  end

  def source_words(other), do: other

  defp truncate(nil), do: "—"

  defp truncate(value) when is_binary(value) do
    if String.length(value) > 60, do: String.slice(value, 0, 60) <> "…", else: value
  end

  defp truncate(other), do: to_string(other)
end
