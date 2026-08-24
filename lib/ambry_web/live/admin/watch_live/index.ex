defmodule AmbryWeb.Admin.WatchLive.Index do
  @moduledoc """
  What the operator is waiting for.

  The list is ordered by who is waiting on whom, the same way the dashboard
  is: what is **due** first, because a date that has passed is the only thing
  here that needs a human; then what is still coming, soonest first; then what
  has been settled. An undated watch sorts after the dated ones — it is a real
  state, but it is not a deadline.

  Nothing on this page decides whether a recording exists. A due watch says
  *the date arrived*, and the operator is the one who knows whether the book
  did.
  """

  use AmbryWeb, :admin_live_view

  alias Ambry.Wanted
  alias Ambry.Wanted.Watch

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: "Watching")
     |> load_watches()}
  end

  defp load_watches(socket) do
    today = Date.utc_today()

    assign(socket, watches: Wanted.list_watches(today: today), today: today)
  end

  @impl Phoenix.LiveView
  def handle_event("mark-released", %{"id" => id}, socket) do
    id |> Wanted.get_watch!() |> Wanted.mark_released()

    {:noreply, socket |> put_flash(:info, "Marked as released.") |> load_watches()}
  end

  def handle_event("dismiss", %{"id" => id}, socket) do
    id |> Wanted.get_watch!() |> Wanted.dismiss()

    {:noreply, socket |> put_flash(:info, "Stopped watching.") |> load_watches()}
  end

  def handle_event("reopen", %{"id" => id}, socket) do
    id |> Wanted.get_watch!() |> Wanted.reopen()

    {:noreply, socket |> put_flash(:info, "Watching again.") |> load_watches()}
  end

  def handle_event("delete", %{"id" => id}, socket) do
    id |> Wanted.get_watch!() |> Wanted.delete_watch()

    {:noreply, socket |> put_flash(:info, "Forgotten.") |> load_watches()}
  end

  @doc """
  What the row says about where this watch stands.

  `:due` is deliberately worded as a question about the date rather than an
  assertion about the book — the provider promised a day, and that day has
  been and gone.
  """
  def state(%Watch{} = watch, today) do
    cond do
      Watch.due?(watch, today) -> :due
      watch.status == :upcoming -> :upcoming
      true -> watch.status
    end
  end

  @doc "How far off the expected date is, in words the operator reads at a glance."
  def when_words(watch, today \\ Date.utc_today())

  def when_words(%Watch{expected_release_date: nil}, _today), do: "No date announced"

  def when_words(%Watch{expected_release_date: date}, today) do
    case Date.diff(date, today) do
      0 -> "Expected today"
      1 -> "Expected tomorrow"
      -1 -> "Was expected yesterday"
      days when days > 1 -> "Expected in #{days} days, on #{format_date(date)}"
      days -> "Expected #{abs(days)} days ago, on #{format_date(date)}"
    end
  end

  defp format_date(date), do: Calendar.strftime(date, "%b %-d, %Y")

  @doc "What to call the provider a record came from."
  defdelegate provider_words(provider_id), to: Ambry.Wanted, as: :provider_name

  @doc "How long the recording is, in words."
  defdelegate runtime(edition), to: Ambry.Wanted.Edition

  @doc """
  The row's variable last line: when it is expected, how long it is, who is
  putting it out.

  Modelled on `record_meta/1` and deliberately not using it: that says
  "Published …", and the whole point of a watch is that it has not been. It
  lives with the credits for the same reason — it is prose and reads like one,
  and it collapses to nothing when a record carries none of it.

  It is **not** `:footer`, which is for system timestamps only. Putting a date
  and a duration there both mislabels them as things the app did and, because
  the footer sits in the 224px rail, stretches the rail until the actions
  stagger and the page scrolls sideways.
  """
  def meta_line(watch, today \\ Date.utc_today()) do
    [
      when_words(watch, today),
      runtime(watch.edition),
      watch.edition.publisher
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" · ")
  end

  @doc """
  The credited names in the shape `credit_lines/1` reads.

  The snapshot keeps names as plain strings — it is a copy of what a provider
  said, not a link to people Ambry knows — so they are wrapped rather than the
  shared component being duplicated for one caller.
  """
  def credited(names), do: Enum.map(names, &%{name: &1})
end
