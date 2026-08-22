defmodule AmbryWeb.Admin.DuplicatesLive.Index do
  @moduledoc """
  Whether the library is holding anything twice.

  ## Why it is a page and not a badge

  Never having duplicates is a standing goal, and every mechanism serving it
  — the seeder linking rather than creating, `Seed.relink/2`, the import
  form's pre-flight — is best effort. A goal that is only ever *pursued* is
  one you have to take on faith. This is the page that answers it, so the
  answer can be looked at rather than believed.

  Which is why an empty report is not an empty page: it says how many records
  it examined. "Nothing found" and "nothing ran" look identical otherwise,
  and the reassuring one is the one you need to be able to trust.

  ## What it does not do

  It does not merge, and it does not offer to. Two records of one name may be
  two spellings of one person or two people who share a name, and the library
  cannot tell them apart — `Ambry.Inbox.Preflight` won't automate that
  judgement at the point of import, so a report that has read even less
  context certainly may not. Each record says what points at it, because the
  question a pair raises is which one can go, and that is answered by the one
  nothing references.

  ## The one thing it can be told

  A set can be marked intentional, because some correct findings have no
  record to remove: the importer's rule folds a companion series into its
  parent, and two spellings of one shelf that an operator keeps apart stay
  found forever otherwise. That is the only action here, and it is the
  opposite of a merge — it says these are two things, not one.

  Marked sets fold rather than vanish, and the empty state says how many
  there are. A page whose whole job is to be believed cannot let "nothing
  found" and "nothing you have not already waved off" read identically, which
  is the same argument that puts the scanned counts at the top.
  """

  use AmbryWeb, :admin_live_view

  alias Ambry.Inbox

  # The order the sections are laid out in, and the whitelist a dismissal's
  # `kind` param is matched against. One list, because a kind the page can
  # draw and a kind it will accept are the same list.
  @kinds ~w(person author narrator book series)a

  @doc """
  The kinds, in the order their sections appear.
  """
  def kinds, do: @kinds

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: "Duplicates", header_title: "Duplicates")
     |> load()}
  end

  @impl Phoenix.LiveView
  def handle_event("reload", _params, socket), do: {:noreply, load(socket)}

  def handle_event("dismiss", %{"kind" => kind, "ids" => ids}, socket) do
    Inbox.dismiss_duplicates(kind(kind), ids(ids))

    {:noreply,
     socket
     |> load()
     |> put_flash(:info, "Marked intentional. It is in the fold at the bottom of this page.")}
  end

  def handle_event("restore", %{"kind" => kind, "ids" => ids}, socket) do
    Inbox.restore_duplicates(kind(kind), ids(ids))

    {:noreply, socket |> load() |> put_flash(:info, "Back in the report.")}
  end

  defp load(socket) do
    report = Inbox.duplicates_report()

    assign(socket,
      found: report.found,
      dismissed: report.dismissed,
      scanned: Inbox.duplicates_scanned()
    )
  end

  # Matched against the kinds rather than `to_existing_atom/1`: the page is
  # admin-only, but a param is a param, and the list is five words long.
  defp kind(value), do: Enum.find(@kinds, &(to_string(&1) == value))

  defp ids(value), do: value |> String.split(",") |> Enum.map(&String.to_integer/1)

  @doc """
  One record in a set: what it is called, and what still points at it.

  The whole row is the link where there is somewhere to go, which is the
  overview's problem-row idiom rather than §3a's — these are not records in a
  list, they are the members of one finding, and a 224px action rail beside
  two lines of text would be the loudest thing on a page whose best day is
  saying nothing.
  """
  attr :kind, :atom, required: true
  attr :record, :map, required: true

  def duplicate_row(assigns) do
    assigns = assign(assigns, navigate: route(assigns.kind, assigns.record))

    ~H"""
    <.link
      :if={@navigate}
      navigate={@navigate}
      class="bg-zinc-800/60 flex items-baseline justify-between gap-4 rounded-md px-3 py-2 hover:bg-zinc-800"
      data-role="duplicate-record"
    >
      <span class="min-w-0 truncate text-sm text-zinc-200">{@record.name}</span>
      <span class={["flex-none text-xs", uses_class(@record)]}>{uses(@record)}</span>
    </.link>

    <div
      :if={!@navigate}
      class="bg-zinc-800/60 flex items-baseline justify-between gap-4 rounded-md px-3 py-2"
      data-role="duplicate-record"
    >
      <span class="min-w-0 truncate text-sm text-zinc-200">{@record.name}</span>
      <span class={["flex-none text-xs", uses_class(@record)]}>{uses(@record)}</span>
    </div>
    """
  end

  # Amber is "needs attention" (§5), and between two records of one name the
  # one nothing references is the half you can actually do something about.
  defp uses_class(%{uses: uses}) do
    if Enum.all?(uses, fn {_word, count} -> count == 0 end),
      do: "text-amber-300",
      else: "text-zinc-400"
  end

  @doc """
  The groups of one kind, in the order the sections are laid out.
  """
  def of_kind(groups, kind), do: Enum.filter(groups, &(&1.kind == kind))

  @doc """
  A set's members, as the value the dismiss and undo buttons carry.
  """
  def ids_value(%{records: records}), do: Enum.map_join(records, ",", & &1.id)

  @doc """
  What an empty report is allowed to claim.

  "Nothing here twice" stops being true the moment a set has been marked
  intentional: those records *are* here twice and the operator has said it is
  fine. Saying the plain thing anyway would make this page the one thing it
  may not be, which is wrong while looking reassuring.
  """
  def all_clear_words([]), do: "Nothing in the library is here twice."

  def all_clear_words(_dismissed), do: "Nothing here twice that you have not already answered."

  @doc """
  The fold's summary.
  """
  def dismissed_words([_one]), do: "1 set marked intentional"
  def dismissed_words(dismissed), do: "#{length(dismissed)} sets marked intentional"

  @doc """
  The heading a kind's section wears, and the sentence under it.

  Kept together because the two have to agree about what the section is for,
  and split across a template they drifted the first time this was written.
  """
  def section(:person),
    do: {"People", "One person, twice. Their photo, bio and credits are split between the two."}

  def section(:author),
    do: {"Authors", "One author name, twice. A book credited to each has no author in common."}

  def section(:narrator),
    do: {"Narrators", "One narrator name, twice. Neither has the other's recordings."}

  def section(:book),
    do:
      {"Books", "One book, twice. Each holds its own audiobooks, so neither page shows them all."}

  # Deliberately hedged: `same_series?/2` folds filler words, so it will pair
  # a real "…: Audio Immersion Tunnel" companion series with its parent.
  def section(:series),
    do: {"Series", "These may be one series under two names, or two that merely rhyme."}

  @doc """
  What points at a record, as a line to read.

  A record nothing references says so in words rather than as a zero, because
  that is the one this page exists to help you act on.
  """
  def uses(%{uses: uses}) do
    case Enum.reject(uses, fn {_word, count} -> count == 0 end) do
      [] -> "Nothing points at this one"
      counted -> counted |> Enum.sort() |> Enum.map_join(" · ", &counted_words/1)
    end
  end

  defp counted_words({word, 1}), do: "1 #{word |> to_string() |> String.trim_trailing("s")}"
  defp counted_words({word, count}), do: "#{count} #{word}"

  @doc """
  Where a record is edited.

  An author and a narrator are edited on the person behind them — there is no
  page of their own — and a narrator always has one. An author may have none
  (a bare name nobody has attached a human to yet) or several (a composite),
  and neither of those has a single place to go, so the row is not a link.
  """
  def route(:person, record), do: ~p"/admin/people/#{record.id}/edit"
  def route(:book, record), do: ~p"/admin/books/#{record.id}/edit"
  def route(:series, record), do: ~p"/admin/series/#{record.id}/edit"

  def route(_author_or_narrator, %{person_id: id}) when is_integer(id),
    do: ~p"/admin/people/#{id}/edit"

  def route(_author_or_narrator, _no_sole_person), do: nil

  @doc """
  What the report covered, for the line under the title.
  """
  def scanned_words(scanned) do
    [
      {scanned.people, "people", "person"},
      {scanned.authors, "authors", "author"},
      {scanned.narrators, "narrators", "narrator"},
      {scanned.books, "books", "book"},
      {scanned.series, "series", "series"}
    ]
    |> Enum.map_join(", ", fn
      {1, _plural, singular} -> "1 #{singular}"
      {count, plural, _singular} -> "#{count} #{plural}"
    end)
  end
end
