defmodule AmbryWeb.Admin.DuplicatesLive.Index do
  @moduledoc """
  Whether the library is holding anything twice.

  Never having duplicates is a standing goal, and every mechanism serving it —
  the seeder linking rather than creating, `Seed.relink/2`, the import form's
  pre-flight — is best effort. This is the page that answers it, so the answer
  can be looked at rather than believed.

  Which is why an empty report is not an empty page: it says how many records
  it examined, since "nothing found" and "nothing ran" look identical
  otherwise.

  It does not merge, and it does not offer to. Two records of one name may be
  two spellings of one person or two people who share a name, and
  `Ambry.Inbox.Preflight` won't automate that judgement at the point of
  import, so a report with even less context may not either. Each record says
  what points at it, because the question a pair raises is which one can go.

  A set can be marked "not a duplicate", because some correct findings have
  no record to remove: the importer's rule folds a companion series into its
  parent, and two spellings of one shelf that an operator keeps apart stay
  found forever otherwise. It is the opposite of a merge — it says these are
  two things, not one.

  Those sets fold rather than vanish, and the report says "no new duplicates"
  rather than "no duplicates" while any are folded away.
  """

  use AmbryWeb, :admin_live_view

  alias Ambry.Inbox

  # The order the sections are laid out in, and the whitelist a dismissal's
  # `kind` param is matched against.
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

  The whole row is the link where there is somewhere to go: the overview's
  problem-row idiom rather than §3a's, because these are the members of one
  finding rather than records in a list.
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

  "No duplicates" stops being true the moment a set has been marked
  otherwise: those records are here twice and the operator has said it is
  fine.
  """
  def all_clear_words([]), do: "No duplicates found."
  def all_clear_words(_dismissed), do: "No new duplicates found."

  @doc """
  The fold's summary, in the words of the button that fills it.
  """
  def dismissed_words(dismissed), do: "#{length(dismissed)} marked not a duplicate"

  @doc """
  The heading a kind's section wears.
  """
  def section(:person), do: "Duplicate people"
  def section(:author), do: "Duplicate authors"
  def section(:narrator), do: "Duplicate narrators"
  def section(:book), do: "Duplicate books"
  def section(:series), do: "Duplicate series"

  @doc """
  What points at a record, as a line to read.

  A record nothing references says so in words rather than as a zero, since
  that is the one to act on.
  """
  def uses(%{uses: uses}) do
    case Enum.reject(uses, fn {_word, count} -> count == 0 end) do
      [] -> "Unused"
      counted -> counted |> Enum.sort() |> Enum.map_join(" · ", &counted_words/1)
    end
  end

  defp counted_words({word, 1}), do: "1 #{word |> to_string() |> String.trim_trailing("s")}"
  defp counted_words({word, count}), do: "#{count} #{word}"

  @doc """
  Where a record is edited.

  An author and a narrator are edited on the person behind them, and a
  narrator always has one. An author may have none or several, and neither of
  those has a single place to go, so the row is not a link.
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
