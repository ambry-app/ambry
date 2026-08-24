defmodule AmbryWeb.Admin.Decisions do
  @moduledoc """
  The building blocks of a staged import: one decision, and one entity
  resolution.

  Deliberately general rather than inbox-specific: every curation surface
  converges here, so "a draft over an existing record, with no file placement"
  is the same form.
  """

  use Phoenix.Component
  use AmbryWeb, :verified_routes

  import AmbryWeb.Admin.Components,
    only: [badge: 1, busy_overlay: 1, disclosure: 1, empty_value: 0, microlabel: 1]

  import AmbryWeb.CoreComponents

  alias Ambry.Books
  alias Ambry.Inbox.Draft.Credit
  alias Ambry.Inbox.Draft.Field
  alias Ambry.Inbox.Draft.GroupLink
  alias Ambry.Inbox.Draft.PersonDecision
  alias Ambry.Inbox.Draft.SeriesLink
  alias Ambry.Inbox.Draft.Tier
  alias Ambry.People
  alias AmbryWeb.Components.EntityDropdown
  alias AmbryWeb.Components.EntityResolver
  alias Phoenix.LiveView.JS

  attr :outcomes, :list, required: true
  attr :level, :string, default: nil
  attr :retrying, :any, default: nil

  attr :retryable, :boolean,
    default: true,
    doc: "person-level outcomes have no per-provider retry yet"

  @doc """
  What each provider said when asked — including the ones that couldn't
  answer.

  Without this a provider that errors is indistinguishable from one that
  found nothing: both contribute zero candidates and say nothing about why.
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

        <%!-- The chip is the retry, so a provider that was rate-limited
            during matching does not cost this item its records until somebody
            re-runs the whole match. --%>
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
            else: unreached_words(outcome)}
        </button>

        <span
          :for={outcome <- @outcomes}
          :if={outcome["status"] == "failed" and not @retryable}
          title={outcome["reason"]}
          class="bg-red-400/10 rounded-sm px-2 py-0.5 text-xs text-red-300"
        >
          {outcome["name"]}: {unreached_words(outcome, retry: false)}
        </span>
      </div>
    </div>
    """
  end

  # A provider that answered by halves says so: one region of a multi-region
  # catalogue being rate-limited is not the provider being down, and the
  # records on screen came from the regions that answered. The count is what
  # came back; the tooltip names the region and why.
  defp unreached_words(outcome, opts \\ [])

  defp unreached_words(%{"partial" => true, "count" => count}, opts) do
    "#{count}, some not reached" <> if(opts[:retry] == false, do: "", else: ", retry")
  end

  defp unreached_words(_outcome, opts) do
    "couldn't be reached" <> if(opts[:retry] == false, do: "", else: ", retry")
  end

  # Where a candidate stops being an alternative and starts being noise. At
  # the boundary rather than below it: a second real recording whose metadata
  # partly contradicts the search scores right about here.
  @worth_showing 0.5

  attr :records, :list, required: true
  attr :used, :any, required: true, doc: "fn record -> boolean, the ticked test"
  slot :row, required: true, doc: "renders one record; receives the record"

  @doc """
  A level's records, with the junk folded away.

  Below `#{@worth_showing}` a record is a search result that shared a word
  rather than a rival reading, so it goes behind a link.

  A ticked record is never hidden, whatever it scores: folding away what the
  operator chose would leave a decision with no visible cause.
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

  # An unscored record is not a weak one: reading a missing score as zero
  # would fold away a record staged before its level ranked anything.
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

  Evidence, not an identity: two providers both holding a record of one book
  is the normal case, and each knows things the other doesn't. Ticking both is
  how the description comes from one and the cover from the other.
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
      <%!-- Identification, not selection: visible BEFORE ticking, while the
          chips below remain where a photo is chosen.

          `object-contain` in a fixed box, because cropping to fill makes a
          portrait print jacket indistinguishable from square audiobook art.
          The box renders empty rather than collapsing. --%>
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
        <%!-- Which database said this holds its width and the title gives
              way: it is a fact about the record rather than one of its own,
              so it wears the badge costume.

              A div, not a p: a div inside a paragraph closes the paragraph
              early. --%>
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
      <%!-- Ranking visible before the number is read: bare percentages carry
            identical visual weight at 100% and at 6%. --%>
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
  question: linking creates nothing and inherits the book's curation, while
  importing a provider record creates a Book.
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
        phx-value-book_id={@book["id"]}
        class={action_classes(:zinc, "flex-none")}
      >
        Yes, another edition of this
      </button>

      <span :if={@linked} class="flex-none text-xs text-zinc-400">using this book</span>
    </div>
    """
  end

  attr :recording, :map, required: true, doc: "an `Ambry.Media.media_option/1` map"

  @doc """
  An audiobook in the library these files might be a better copy of.

  The work level's local-book costume, asking a different question: not
  "which book is this" but "is this an audiobook you already have, in better
  files".

  Only ever a proposal: the answer lives in the picker beside it.
  """
  def local_recording_row(assigns) do
    ~H"""
    <div class="bg-zinc-800/60 flex items-start gap-3 rounded-md p-3" data-role="local-recording">
      <div class="min-w-0 flex-grow">
        <p class="truncate text-sm font-semibold">{@recording.label}</p>
        <p class="truncate text-xs text-zinc-400">{@recording.detail}</p>
      </div>

      <button
        type="button"
        phx-click="replace-recording"
        phx-value-media_id={@recording.id}
        class={action_classes(:zinc, "flex-none")}
      >
        Yes, replace its files
      </button>
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
  attr :label, :string, default: "Search"
  attr :running, :boolean, default: false

  attr :standalone, :boolean,
    default: true,
    doc: "false where this sits inside a form that is not its own — see `person_card/1`"

  attr :query_event, :string,
    default: "person-query",
    doc: "not standalone: what the box raises as it is typed into"

  @doc """
  The person level's search-again form — the work-level pattern with a name
  where the work has title and author.

  The box holds the *query*, never the person's name decision: bound to the
  decision, a search for anything else snaps back to the pre-filled name the
  moment the results land.

  One component for every people search in the admin, parameterised by which
  event routes it and whether there is a person key to route *to*.
  """
  def person_research_form(%{standalone: true} = assigns) do
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

  # The same box, minus the form element it cannot have here.
  #
  # The query is not one of the enclosing form's values: as one it would post
  # back whatever the card first rendered with and then win every render
  # against the name it is supposed to be following. It is view state, so it
  # lives in the socket, and `phx-keyup` is how a box with no form of its own
  # says what it holds.
  def person_research_form(assigns) do
    ~H"""
    <div class="flex flex-wrap items-end gap-2">
      <label class="text-xs text-zinc-400">
        <span class="block pl-3">name</span>
        <input
          type="text"
          value={@name}
          phx-keyup={@query_event}
          phx-value-key={@person_key}
          phx-debounce="300"
          class={input_classes("mt-1 block")}
        />
      </label>

      <.button
        color={:zinc}
        type="button"
        phx-click={@event}
        phx-value-key={@person_key}
        phx-value-name={@name}
        disabled={@running or @name in [nil, ""]}
      >
        {if @running, do: "Searching…", else: @label}
      </.button>
    </div>
    """
  end

  attr :level, :string, required: true
  attr :fields, :map, required: true
  attr :running, :boolean, default: false

  attr :label, :string,
    default: "Search again",
    doc: ~s(the edit forms' fresh panel says "Search" — nothing was searched yet)

  attr :scan_files, :boolean,
    default: false,
    doc: "offer the files on their own — see `AmbryWeb.Admin.Curation.evidence_panel/1`"

  @doc """
  An editable version of the search that produced these records.

  For the case the stored candidate list cannot cover: the right answer isn't
  in it at all, usually because a wrong tag sent the search somewhere
  strange.
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

      <%!-- Full height, because adjacent bar controls share exact height (§7).
          The `sm` costume would leave it short beside every input. --%>
      <.button color={:zinc} type="submit" disabled={@running}>
        {if @running, do: "Searching…", else: @label}
      </.button>

      <%!-- Its own control: paired with the provider fan-out, asking "is the
            embedded cover better?" would cost a round trip to every
            database that has heard of the book. --%>
      <.button
        :if={@scan_files}
        color={:zinc}
        type="button"
        phx-click="scan-files"
        disabled={@running}
      >
        Read files only
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

  Narrator and year lead because they tell two recordings of one work apart.

  Which database said so is not one of them: that is what the operator weighs
  the record by rather than what tells it apart, so it is a badge on the
  row.
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

  # The first words of the bio are what tells a namesake apart.
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

  The candidates stay visible after one is chosen: hiding them makes the
  choice feel final when the point is that it is reviewable.
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

        <%!-- Only when it says something the rail can't: a badge repeating
            "needs confirming" beside an amber rail is the same fact twice
            (§2). --%>
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
        <%!-- A URL in a text box is not a cover, and its dimensions matter: a
              thumbnail and a full-size cover look identical here. Proxied
              (§7) or tracking protection blocks the provider CDN. --%>
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
                  written blind. --%>
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

          <%!-- Choosing "none" is an approval, not an omission: it makes "every
                piece is settled" reachable on a record with empty optional
                fields. Ghost, because it is an escape hatch. --%>
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
  attr :verb, :string, required: true, doc: ~s(the visible label — "Written by")
  attr :persons, :list, required: true, doc: "the PersonDecisions this credit references"

  attr :count, :integer,
    default: 1,
    doc: "how many rows the list holds — the reorder arrows' ends"

  @doc """
  One credit, resolved to an identity.

  One control by default: a credited name IS an identity, and how many humans
  stand behind it is a fact about the person that no provider reports. The
  person layer is a section of its own and the credit references it.

  The name is editable, because a provider's spelling is a proposal like any
  other.

  A link decision always targets an identity, never a Person, or matching
  links whichever identity happens to be first.
  """
  # Removed is a tombstone the operator can take back: a ghost row holding
  # the name and a restore, out of the decision queue.
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
    assigns = assign(assigns, :faces, Enum.map(assigns.persons, &person_face/1))

    ~H"""
    <%!-- A decision block, so it wears the state rail like every other one.
        The rail is the ONLY settledness encoding (§2): a check icon appearing
        on approval would shift the title sideways. --%>
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

      <%!-- Beside the box, not under it: a credit is one line of meaning, and
            a full-cast recording is a run of these rows. --%>
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
            search={identity_search(@credit.kind)}
            fetch={identity_fetch(@credit.kind)}
            value={if @credit.mode == :link, do: @credit.identity_id}
            text={@credit.name || ""}
            placeholder="name"
            class={input_classes("w-full")}
          />

          <%!-- Only speaks when the linked identity is backed by other humans:
                the prefix segment already says "Existing". --%>
          <span
            :if={identity_backing(@credit)}
            class="text-xs text-zinc-400"
            data-role="identity-backing"
          >
            {identity_backing(@credit)}
          </span>
        </form>

        <%!-- A reference, not the person: one human is one record, living
              once in the People section. --%>
        <.credit_people
          :if={@credit.mode == :create}
          id={"credit-people-#{@section}-#{@index}"}
          faces={@faces}
        />
      </div>

      <%!-- The way back after a rename or a clear, in the same chip the
            scalar fields wear. Only speaks while the box disagrees with the
            evidence; a linked identity has the library's own name. --%>
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

  attr :id, :string, required: true
  attr :faces, :list, required: true, doc: "`person_face/1` maps — key, name, and a src or nil"
  attr :section_href, :string, default: "#people", doc: "where the overflow pill goes"

  attr :class, :any,
    default: nil,
    doc:
      "beside a picker rather than inside a card, this is one input tall — see `delete_button/1`"

  @doc """
  Who a credit means, as a link to their card.

  A reference, not the person: one human is one record, living once in the
  People section.

  The link flashes what it lands on (`assets/js/hooks/flash-target.js`),
  because an anchor jump on a long form gives no indication of which card was
  meant.
  """
  def credit_people(assigns) do
    ~H"""
    <div
      :if={@faces != []}
      id={@id}
      phx-hook="flash-target"
      class={["flex flex-none flex-wrap gap-2", @class]}
      data-role="credit-people"
    >
      <.link
        :for={face <- Enum.take(@faces, person_chips())}
        href={"#person-#{face.key}"}
        class="bg-white/5 flex items-center gap-2 rounded-full py-1 pr-3 pl-1 text-xs text-zinc-300 hover:bg-white/10"
      >
        <img :if={face.src} src={face.src} class="h-6 w-6 flex-none rounded-full object-cover" alt="" />
        <span :if={!face.src} class="h-6 w-6 flex-none rounded-full bg-zinc-800" />
        {face.name}
      </.link>

      <%!-- A dozen humans behind one credit would make the row a paragraph of
            faces; the rest are a click away in the People section. --%>
      <.link
        :if={length(@faces) > person_chips()}
        href={@section_href}
        title={Enum.map_join(Enum.drop(@faces, person_chips()), ", ", & &1.name)}
        class="bg-white/10 flex items-center rounded-full px-3 py-1 text-xs tabular-nums text-zinc-300 hover:bg-white/20"
      >
        +{length(@faces) - person_chips()}
      </.link>
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

  attr :query_name, :string,
    default: nil,
    doc: "the name these records were searched for; falls back to the person's own"

  attr :at, :string,
    default: nil,
    doc:
      "what this card's DOM ids are built from. Defaults to the credit's address, which is " <>
        "unique where a card is one of a draft's; a surface that renders cards outside that " <>
        "grid has to say. See `person_curation/1`."

  attr :input_prefix, :string,
    default: nil,
    doc:
      "set where the card sits INSIDE a form that is not its own — the name its controls post " <>
        "under. See \"One card, two form owners\" below."

  attr :link_input, :string,
    default: nil,
    doc: "with `input_prefix`: the input the local rows write, which is the join's `person_id`"

  attr :list_sort_name, :string,
    default: nil,
    doc:
      "with `input_prefix`: the sort param of the list this card is a row of. Adding and " <>
        "removing a person are Ecto's own list gestures there, where the inbox raises events."

  attr :list_drop_name, :string, default: nil, doc: "with `input_prefix`: that list's drop param"

  @doc """
  One human this import will create, as a decision card of their own.

  A person's own questions (what they are called, which face, which
  biography) live here, separately from the *credit*, which asks which
  identity this book credits.

  The name box is the exception, not the furniture: a credited name is the
  human's name in almost every import, so the card states it and the box
  appears only when the name is genuinely the person's own.

  Events address the credit that introduces them (`section`, `index`,
  `person_index`): a person exists only as long as a credit names them.

  One card, two form owners. The import form saves on change and has no form
  of its own, so each control here is a little `<form>`; an edit form is one
  form with a Save button, and forms cannot nest. Given an `input_prefix`,
  the three form-bearing controls become plain inputs posting under it and
  the chips write those inputs on the client
  (`assets/js/hooks/set-input.js`).
  """
  def person_card(assigns) do
    assigns =
      assign(assigns,
        own_name: assigns.person.own_name or not Credit.simple?(assigns.group.credit),
        linked: linked_person(assigns.person),
        # A linked person is called what the library calls them: the staged
        # name is a leftover of finding them.
        words: person_words(assigns.person, linked_person(assigns.person))
      )

    ~H"""
    <%!-- No rail where the card is inside an edit form: a rail says how far
        through a decision this is, and an edit form has no decision tree to
        be part-way through (design language §9). --%>
    <div
      id={"person-#{@person.key}"}
      phx-hook={@input_prefix && "set-input"}
      class={["relative space-y-3 rounded-lg bg-zinc-900 p-4", is_nil(@input_prefix) && ["border-l-4", state_rail(@person)]]}
      data-role="person-card"
    >
      <%!-- The card is not yours while a provider round-trip runs. A button
            relabelling itself is not enough, especially inside a fold that
            can close over it. --%>
      <%!-- Named by the QUERY: a search for a name other than this person's
            own would claim to be looking for them. --%>
      <.busy_overlay busy={@searching} label={"Looking for #{@query_name || @words}…"} />

      <div class="space-y-3" inert={@searching}>
        <%!-- Titled by the CREDIT, the one name here that doesn't move: the box
              below is the human's name, and a header following it re-titles
              the card letter by letter as it is typed. --%>
        <div class="flex items-baseline justify-between gap-2 pl-3">
          <div class="flex min-w-0 items-baseline gap-2">
            <.label>{card_words(@group.credit, @words)}</.label>

            <%!-- A fact about this card, so it wears the status costume beside
                  the title rather than a sentence under it. --%>
            <.badge :if={@appears != []} color={:gray} class="text-xs">
              {credited_words(@appears)}
            </.badge>
          </div>

          <button
            :if={@removable}
            type="button"
            phx-click={(@list_drop_name && JS.dispatch("change")) || "remove-person"}
            phx-value-section={@group.section}
            phx-value-index={@group.index}
            phx-value-person={@person_index}
            name={@list_drop_name && @list_drop_name <> "[]"}
            value={@list_drop_name && @person_index}
            title="not one of the people behind this name"
          >
            <.icon name="fa-xmark" class="h-3 w-3 cursor-pointer hover:text-red-600" />
          </button>
        </div>

        <%!-- Which human this join points at, where the card is inside a form.
              The local rows below write it; a blank one means the person on
              this card is being created. --%>
        <input
          :if={@link_input}
          type="hidden"
          name={@link_input}
          value={@person.mode == :link && @person.person_id}
        />

        <%!-- One human on two credits is the ordinary reason a name appears
              twice, so it is the default and the badge above says which two.
              This is the escape hatch, asked once per person. --%>
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

        <%!-- The usual case: the credit names the human and the card asks
              nothing. The link is the whole line, since a card titled by the
              credit saying "named by the credit" is one fact twice. --%>
        <p :if={@person.mode == :create and !@own_name} class="pl-3 text-xs text-zinc-400">
          <%!-- The key travels beside the credit's address: an edit form's card
                is keyed by the row it hangs off and has no section to name. --%>
          <button
            type="button"
            phx-click="separate-name"
            phx-value-section={@group.section}
            phx-value-index={@group.index}
            phx-value-key={@person.key}
            class="underline"
          >
            {reveal_words(@group.kind)}
          </button>
        </p>

        <%!-- The exception, revealed: without a box to overrule it, a pen name
              could only ever be imported as a person of that name. The
              typeahead is also how they become somebody the library has. --%>
        <div :if={@person.mode == :create and @own_name} class="space-y-1">
          <p class="pl-3 text-xs text-zinc-400">{alias_words(@group.kind)}</p>

          <.identity_box person={@person} input_prefix={@input_prefix} link_input={@link_input} />

          <%!-- Both escape hatches from the same state, on the rail under
                the box they belong to. A shared pen name is asked here
                rather than on the credit, where it would change a card out
                of view. --%>
          <div class="flex flex-wrap items-baseline gap-x-4 pl-3 text-xs text-zinc-400">
            <span :if={@group.section == "work"}>
              Is this pen name more than one person?
              <button
                type="button"
                phx-click={(@list_sort_name && JS.dispatch("change")) || "add-person"}
                phx-value-section={@group.section}
                phx-value-index={@group.index}
                name={@list_sort_name && @list_sort_name <> "[]"}
                value={@list_sort_name && "new"}
                class="underline"
              >
                Add a person
              </button>
            </span>

            <%!-- Every way in needs a way out: a reveal that cannot be
                  folded back is a one-way door. --%>
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

        <%!-- A different KIND of question from the provider records below: those
              describe a human, this one IS one, and choosing them creates
              nobody. --%>
        <div :if={@locals != [] or @person.mode == :link} class="space-y-2">
          <p class="pl-3 text-xs text-zinc-400">
            {local_people_words(@person, @locals, @group.kind)}
          </p>

          <.local_person_row
            :for={local <- @locals}
            local={local}
            person_key={@person.key}
            link_input={@link_input}
            chosen={@person.mode == :link and to_string(@person.person_id) == to_string(local["id"])}
          />

          <%!-- Linked to somebody the name search never offered (the typeahead
                above), so the row is built from the library instead. --%>
          <.local_person_row
            :if={
              @person.mode == :link and
                not Enum.any?(@locals, &(to_string(&1["id"]) == to_string(@person.person_id)))
            }
            local={@linked}
            person_key={@person.key}
            link_input={@link_input}
            chosen={true}
          />
        </div>

        <.person_curation
          person={@person}
          at={@at}
          input_prefix={@input_prefix}
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

  attr :person, PersonDecision, required: true
  attr :input_prefix, :string, default: nil
  attr :link_input, :string, default: nil

  # The one control that has to know who owns the form: its own `<form>`
  # where the card is the only form on the page, a plain input where it isn't.
  defp identity_box(%{input_prefix: nil} = assigns) do
    ~H"""
    <form id={"person-#{@person.key}-identity"} phx-change="person-change">
      <input type="hidden" name="key" value={@person.key} />
      <.person_resolver person={@person} name="person_id" text_name="name" />
    </form>
    """
  end

  # The id belongs to the JOIN, not to the person: picking somebody the
  # library has means this credit points at them, and under the nested person
  # the pick lands on a field nothing casts.
  defp identity_box(assigns) do
    ~H"""
    <.person_resolver
      person={@person}
      name={@link_input}
      text_name={@input_prefix <> "[name]"}
    />
    """
  end

  attr :person, PersonDecision, required: true
  attr :name, :string, required: true
  attr :text_name, :string, required: true

  defp person_resolver(assigns) do
    ~H"""
    <.live_component
      module={EntityResolver}
      id={"person-#{@person.key}-resolver"}
      name={@name}
      text_name={@text_name}
      search={&People.search_people/2}
      fetch={&People.person_option/1}
      value={nil}
      text={Field.value(@person.name) || ""}
      placeholder="the person's real name"
      class={input_classes("w-full")}
    />
    """
  end

  defp person_words(_person, %{"name" => name}), do: name
  defp person_words(person, nil), do: Field.value(person.name) || "Unnamed person"

  # The credited name, which is what this card is about. Falls back to the
  # human's own name only when the credit has none, mid-retype.
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
  defp linked_person(%PersonDecision{mode: :link, person_id: id}) do
    case People.person_option(id) do
      nil -> %{"id" => id, "name" => "Somebody in your library"}
      person -> %{"id" => person.id, "name" => person.label, "image" => person.image}
    end
  end

  defp linked_person(_person), do: nil

  @doc """
  What to show for a person: the library's own name and face where this
  decision links to one, the staged fields where it will create one.

  A linked decision keeps whatever was typed on the way to finding them, so
  unlinking can give it back, but rendering that would show a half-typed name
  beside the linked person's portrait.

  The src is resolved here: a library thumbnail is a local path served as-is,
  a staged image may be a remote URL needing the proxy.
  """
  def person_face(person) do
    case linked_person(person) do
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

  # Linking answers "who is this" and a pen name answers "whose name is on
  # the book"; the second doesn't stop being true because the first was
  # answered from the library.
  defp local_people_words(%PersonDecision{mode: :link, own_name: true}, _locals, kind),
    do: alias_words(kind)

  defp local_people_words(%PersonDecision{mode: :link}, _locals, _kind),
    do: "This import will use the person you already have."

  defp local_people_words(_person, [_one], _kind),
    do: "Somebody by this name is already in your library."

  defp local_people_words(_person, locals, _kind),
    do: "#{length(locals)} people by this name are already in your library."

  # Which records a control offers is a property of what it is picking, not
  # a decision the caller makes: a "Written by" row can only ever resolve an
  # Author. Naming the source here is what keeps the form from loading every
  # identity in the library on mount.
  defp identity_search(:author), do: &People.search_authors/2
  defp identity_search(:narrator), do: &People.search_narrators/2

  defp identity_fetch(:author), do: &People.author_option/1
  defp identity_fetch(:narrator), do: &People.narrator_option/1

  # Who is really behind a linked identity, when the names add something.
  # Read off the one record this credit points at.
  defp identity_backing(%Credit{mode: :link, kind: kind, identity_id: id}) when not is_nil(id) do
    case identity_fetch(kind).(id) do
      %{detail: detail} -> detail
      nil -> nil
    end
  end

  defp identity_backing(%Credit{}), do: nil

  attr :local, :map, required: true
  attr :person_key, :string, required: true
  attr :chosen, :boolean, required: true

  attr :link_input, :string,
    default: nil,
    doc: "where the card is inside a form: the input this row writes rather than an event"

  @doc """
  A person the library already has, offered instead of creating another.

  The same question the local-book row asks, one level down: reusing a human
  is the outcome worth having, and the form's job is to make it one click
  rather than a duplicate nobody notices.
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
        phx-click={!@link_input && "link-person"}
        phx-value-key={@person_key}
        phx-value-id={@local["id"]}
        data-set-input={@link_input}
        data-set-value={@link_input && to_string(@local["id"])}
        class={action_classes(:zinc, "flex-none")}
      >
        Yes, it's them
      </button>

      <button
        :if={@chosen}
        type="button"
        phx-click={!@link_input && "unlink-person"}
        phx-value-key={@person_key}
        data-set-input={@link_input}
        data-set-value={@link_input && ""}
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
  That two credits mean one person is a line of its own, since it comes with
  a control.
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

  attr :at, :string, default: nil, doc: "see below — overrides where these ids are keyed"

  attr :input_prefix, :string,
    default: nil,
    doc: "see `person_card/1` — set where the card sits inside a form that is not its own"

  # Enough to see there are alternatives without the row becoming a contact
  # sheet: a working actor can have dozens of headshots on file.
  @photo_preview 5

  @doc """
  The face and bio a new person will be created with.

  A person with no face is unfinished, and the operator should never have to
  leave the inbox to finish one.

  No modal: a person's description wants the same editable text box with the
  same proposals underneath it that a recording's does. The photos are chips
  too, circular and at the size they will be seen, because the decision is
  whether a face survives a circular crop. Past the first few they fold away.

  One human is one record, so the same photo appears in both credits because
  it is the same photo, not because two copies are kept in step.

  The candidates arrive with the item. "Look again" is for a name that has
  *changed* since.
  """
  def person_curation(assigns) do
    assigns =
      assign(assigns,
        # These ids have to be unique in the document, and the address is
        # only unique where a card is one of a draft's. An import form's
        # people are a grid, so keying by where a card is rather than by who
        # it is tells two renderings of one human apart. An edit form has no
        # such grid: every card would claim the same address and its
        # hook-bearing elements would collide, which patches the wrong DOM.
        # So a caller with a better answer gives it; the person key travels
        # in the form's hidden field either way.
        at: assigns.at || "#{assigns.section}-#{assigns.index}-#{assigns.person_index}",
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

        <%!-- Inside a form the chosen face is one of that form's values and needs
              an input to live in. On the inbox the decision is the draft's,
              and there is nothing to post. --%>
        <input
          :if={@input_prefix}
          type="hidden"
          name={@input_prefix <> "[image_import_url]"}
          value={@image}
        />
      </div>

      <%!-- The same three parts in the same order as the work and recording
            levels, under the same name: the query, who answered, and what
            they said. --%>
      <.microlabel class="block pl-3">Provider records</.microlabel>

      <.person_research_form
        at={@at}
        person_key={@person.key}
        name={@query_name || Field.value(@person.name)}
        running={@searching}
        standalone={is_nil(@input_prefix)}
      />

      <.provider_outcomes_row outcomes={@outcomes} retryable={false} />

      <%!-- Nothing found is a normal outcome, not a failure — plenty of
            narrators are in no database at all — but it should say so rather
            than looking like an empty grid nobody filled in. --%>
      <p :if={@person.doubt == :low_confidence} class="pl-3 text-xs text-zinc-400">
        {@person.doubt_detail}
      </p>

      <%!-- Folded on the same threshold as the other levels: eight rows of
            equal weight is how the wrong human stays in the running. A
            ticked record is never folded. --%>
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

      <%!-- The same answer the other two levels have: a doubted person stays
            outstanding until somebody says so, and it costs nothing but the
            photo and the biography.

            Records about this name arrive ticked, so "none of these is my
            narrator" needs saying, and it is one click against unticking
            every row by hand. Inside a form the fields are inputs, so the
            button empties them the way the chips fill them. --%>
      <div :if={@records != []} class="flex flex-wrap items-center gap-2 pt-1">
        <button
          type="button"
          phx-click="uncatalogued-person"
          phx-value-key={@person.key}
          data-set-blank={@input_prefix && blank_targets(@input_prefix)}
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

      <%!-- Shown while there is a face OR faces to choose from: a photo whose
            record was since unticked would leave a chosen face with no strip
            under it, and the strip is the way out. --%>
      <div
        :if={@photos != [] or @image}
        class="grid-cols-[4rem_minmax(0,1fr)] grid items-start gap-x-2 pl-3"
      >
        <.microlabel class="pt-1">Photos</.microlabel>

        <div class="flex flex-wrap items-center gap-2">
          <.proposal_chip
            :for={photo <- shown_photos(@photos, @expanded)}
            chosen={Field.chose?(@person.image, photo)}
            event="pick-person-image"
            values={%{"key" => @person.key, "candidate" => photo.key}}
            writes={writes(@input_prefix, "[image_import_url]", photo.value)}
            title={photo.label}
            shape="circle"
          >
            <.image_with_size
              id={"photo-#{@at}-#{:erlang.phash2(photo.value)}"}
              src={proxied_remote_image_url(photo.value)}
              class="h-16 w-16 rounded-full object-cover object-top"
            />
          </.proposal_chip>

          <%!-- No face is one of the faces: a person with no picture is a
              perfectly good answer, so it sits in the strip wearing the same
              ring when it is in force. --%>
          <.proposal_chip
            chosen={is_nil(@image)}
            shape="circle"
            event="waive-person-field"
            values={%{"key" => @person.key, "field" => "image"}}
            writes={writes(@input_prefix, "[image_import_url]", "")}
            title="no photo"
          >
            <span class="flex h-16 w-16 items-center justify-center rounded-full border border-dashed border-zinc-600 text-xs text-zinc-400">
              none
            </span>
          </.proposal_chip>

          <%!-- The point is that alternatives EXIST, not that a dozen headshots
              are all on show. --%>
          <button
            :if={length(@photos) > photo_preview()}
            type="button"
            phx-click="toggle-photos"
            phx-value-key={@person.key}
            class="text-xs text-zinc-400 underline"
          >
            {if @expanded, do: "show fewer", else: "show all #{length(@photos)} photos"}
          </button>
        </div>
      </div>

      <%!-- The same text box the recording's description gets, for the same
            reason: an imported blurb is a starting point. --%>
      <div class="space-y-1">
        <div class="grid grid-cols-1 gap-2 sm:grid-cols-2">
          <.bio_box
            at={@at}
            person_key={@person.key}
            description={@description}
            input_prefix={@input_prefix}
          />
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
              writes={writes(@input_prefix, "[description]", bio.value)}
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

  attr :at, :string, required: true
  attr :person_key, :string, required: true
  attr :description, :string, default: nil
  attr :input_prefix, :string, default: nil

  # The other control that has to know who owns the form. Same box, same
  # preview beside it; only the wrapper and the name change.
  defp bio_box(%{input_prefix: nil} = assigns) do
    ~H"""
    <form id={"person-bio-#{@at}"} phx-change="person-bio" phx-submit="person-bio">
      <input type="hidden" name="key" value={@person_key} />
      <.bio_input at={@at} name="description" description={@description} />
    </form>
    """
  end

  defp bio_box(assigns) do
    ~H"""
    <.bio_input at={@at} name={@input_prefix <> "[description]"} description={@description} />
    """
  end

  attr :at, :string, required: true
  attr :name, :string, required: true
  attr :description, :string, default: nil

  defp bio_input(assigns) do
    ~H"""
    <textarea
      id={"person-bio-#{@at}-input"}
      name={@name}
      rows="3"
      placeholder="a short bio"
      phx-debounce="500"
      phx-hook="maintain-attrs"
      data-attrs="style"
      class={input_classes("block w-full")}
    >{@description}</textarea>
    """
  end

  # A chip's other job, on a surface where the value is an input rather than
  # a decision the server holds.
  defp writes(nil, _suffix, _value), do: nil
  defp writes(prefix, suffix, value), do: %{input: prefix <> suffix, value: value}

  # Everything "none of these" takes back, which is everything a record ever
  # gave this person: the face and the biography. The name is theirs.
  defp blank_targets(prefix),
    do: Jason.encode!([prefix <> "[image_import_url]", prefix <> "[description]"])

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

  attr :event, :string,
    default: nil,
    doc: "the click, where the server owns the decision; nil where the chip writes an input"

  attr :rest, :global, include: ~w(disabled)

  attr :writes, :map,
    default: nil,
    doc:
      ~s(`%{input: name, value: value}` — a chip on a surface where the value is a form input ) <>
        ~s(rather than a decision the server holds. It sets that input and dispatches a change ) <>
        ~s(\(`assets/js/hooks/set-input.js`\) instead of raising `event`.)

  attr :inert, :boolean,
    default: false,
    doc: "when chosen, this chip is a statement rather than an offer — see below"

  attr :values, :map, default: %{}
  attr :title, :string, default: nil
  attr :shape, :string, default: "text"
  attr :ghost, :boolean, default: false, doc: ~s(escape hatches like "None" — dashed and quiet)
  slot :inner_block, required: true

  @doc """
  One proposal, and whether it's the one in use.

  Shared by every place the form offers alternatives (a scalar's candidates, a
  person's photos, a person's bios): the same interaction, so the same markup.

  **`inert` is for a chip that adds a row**, where clicking a chosen one would
  append the entity it is already reporting. It renders as a plain span with
  the same costume and no click, and becomes an offer again the moment it
  stops being true.

  Chosen chips elsewhere stay live: clicking the one already in use is how a
  decision gets confirmed, leaving the value alone and turning the rail green.
  """
  def proposal_chip(%{chosen: true, inert: true} = assigns) do
    ~H"""
    <span
      title={@title}
      {@rest}
      class={[
        "bg-brand-dark/15 ring-brand-dark/50 max-w-full rounded-md text-left text-xs ring-2 ring-inset",
        @shape == "circle" && "rounded-full p-0.5",
        @shape != "circle" && "inline-flex items-center gap-1.5 px-2 py-1"
      ]}
    >
      <%!-- The most important state on the form, so it says so three ways:
            border, tint and a check. A border-hue change alone is invisible. --%>
      <.icon :if={@shape != "circle"} name="fa-check" class="text-brand-dark h-3 w-3 flex-none" />
      {render_slot(@inner_block)}
    </span>
    """
  end

  def proposal_chip(assigns) do
    ~H"""
    <button
      type="button"
      phx-click={!@writes && @event}
      {chip_values(@values)}
      data-set-input={@writes && @writes.input}
      data-set-value={@writes && @writes.value}
      {@rest}
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
    <%!-- The same anatomy as every other decision block: railed header row,
        state on the left rail and nowhere else (§2), controls below. --%>
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

          <%!-- Every decision block says where its answer came from, and a series
              membership is a proposal like any other. --%>
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
          the number wears no label: a placeholder alone is how this field is
          spelled everywhere, and a label over one box of two makes the row
          tall and the two controls' tops disagree. --%>
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
            search={&Books.search_series/2}
            fetch={&Books.series_option/1}
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

  attr :book_id, :any,
    default: nil,
    doc: "the book whose sets this offers — a set belongs to a book the way its members do"

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

      <%!-- The cross-item case this row exists for: an earlier part created the
          set, and joining it keeps one work from growing a second. --%>
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
        <%!-- Two controls, not one box that infers which you meant. Whether the
            book has a set to join is knowable, so the form says so rather
            than making the operator discover it by typing.

            A typeahead would search for sets belonging to a book that usually
            does not exist yet, so its whole answer is the box echoed back,
            and it would leave the mode inferred from whether what you typed
            happened to match. --%>
        <form
          id="group-link"
          phx-change="link-group"
          class="min-w-48 flex max-w-md flex-grow items-start gap-2"
        >
          <%!-- **`flex-1 min-w-0`, not `w-full`.** Two `w-full` children of a flex
              row shrink in proportion to their *content*, so one crushes the
              other. Basis-zero splits the column evenly. --%>
          <div :if={@link.candidates != []} class="min-w-0 flex-1">
            <%!-- Stated here, unlike every other control on this row:
                `@tailwindcss/forms` gives `input`, `select` and `textarea`
                their padding and border, but a drop-down's trigger is a
                `button`, which it never touches. The plugin's own numbers,
                so it sits level with the boxes beside it. --%>
            <.live_component
              module={EntityDropdown}
              id="group-dropdown"
              name="recording_group_id"
              options={group_options(@link)}
              value={group_choice(@link)}
              class={input_classes("w-full border px-3 py-2")}
            />
          </div>

          <input
            :if={@link.mode == :create}
            type="text"
            name="name"
            value={@link.name}
            placeholder="set name"
            phx-debounce="500"
            class={input_classes("w-full min-w-0 flex-1")}
            data-role="group-name"
          />
        </form>

        <%!-- `w-20` on both: "total" clips in the narrower one, and two number
              boxes of different widths read as an accident. --%>
        <form id="group-part" phx-change="set-group-part" class="flex-none">
          <input
            type="number"
            min="1"
            name="part_number"
            value={@link.part_number}
            placeholder="no."
            class={input_classes("w-20")}
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
            class={input_classes("w-20")}
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

  # The sets this recording could join, plus the one row that means "none of
  # these". `@new_group` rather than "" because an empty id can never read as
  # chosen — `EntityOption.selected?/2` treats a blank value as nothing held,
  # which is right everywhere else.
  @new_group "new"

  defp group_options(%GroupLink{} = link) do
    Enum.map(link.candidates, fn candidate ->
      %{
        id: candidate.recording_group_id,
        label: candidate.name,
        detail: candidate.parts_total && "#{candidate.parts_total} parts"
      }
    end) ++ [%{id: @new_group, label: "New set"}]
  end

  defp group_choice(%GroupLink{mode: :link, recording_group_id: id}), do: id
  defp group_choice(%GroupLink{}), do: @new_group

  @doc """
  The block's left rail — the one thing that encodes settledness (§2).

  Four tiers rather than settled-versus-waiting, which throws away the
  question an operator actually asks of a machine-matched import: has anyone
  looked at this yet. A 4px rail renders crisp at DPIs where a tinted hairline
  goes mushy.

  `:uncatalogued` shares amber with `:waiting`, because the rail says *how
  settled* rather than *what to do about it*. The badge beside it is where the
  two part company.
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

  A queue row is one line with nowhere to put a 4px edge per level, so it says
  the same states in words. Same vocabulary as the form's rail, from one
  place, or the two drift.

  `:uncatalogued` is the tier the words say more than the rail does: it shares
  amber with `:waiting`, but "nothing found" and "needs you" ask for different
  things and "matched" over an empty candidate list says neither.
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

  # A group proposal seeds its own words for these two, so drafts can carry
  # either spelling.
  def source_words("name"), do: "the release name"
  def source_words("library"), do: "the library"

  def source_words("provider:" <> id = source) do
    case Ambry.Metadata.Registry.fetch(id) do
      {:ok, entry} -> entry.display_name
      {:error, :unknown_provider} -> source
    end
  end

  def source_words(other), do: other

  defp truncate(nil), do: empty_value()

  defp truncate(value) when is_binary(value) do
    if String.length(value) > 60, do: String.slice(value, 0, 60) <> "…", else: value
  end

  defp truncate(other), do: to_string(other)
end
