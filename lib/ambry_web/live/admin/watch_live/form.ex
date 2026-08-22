defmodule AmbryWeb.Admin.WatchLive.Form do
  @moduledoc """
  Editing a watch — the date, the state, and a note to self.

  The snapshot is not editable. It is a copy of what a provider said at the
  moment the operator chose it, and letting it be rewritten would turn the one
  record of *what was actually picked* into something that merely agrees with
  the current opinion.

  The **date** is editable, because that is the field the world changes:
  publishers move release dates and providers lag behind them, so the operator
  frequently knows before the provider does.
  """

  use AmbryWeb, :admin_live_view

  alias Ambry.Wanted
  alias Ambry.Wanted.Watch

  @impl Phoenix.LiveView
  def mount(%{"id" => id}, _session, socket) do
    watch = Wanted.get_watch!(id)

    {:ok,
     socket
     |> assign(
       page_title: watch.edition.title,
       watch: watch,
       form: to_form(Wanted.change_watch(watch))
     )}
  end

  @impl Phoenix.LiveView
  def handle_event("delete", _params, socket) do
    {:ok, _watch} = Wanted.delete_watch(socket.assigns.watch)

    {:noreply,
     socket
     |> put_flash(:info, "Forgotten.")
     |> push_navigate(to: ~p"/admin/watches")}
  end

  def handle_event("validate", %{"watch" => params}, socket) do
    changeset = Wanted.change_watch(socket.assigns.watch, params)

    {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"watch" => params}, socket) do
    case Wanted.update_watch(socket.assigns.watch, params) do
      {:ok, _watch} ->
        {:noreply,
         socket
         |> put_flash(:info, "Saved.")
         |> push_navigate(to: ~p"/admin/watches")}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  @doc false
  def status_options do
    [
      {"Waiting for it", :upcoming},
      {"It's out", :released},
      {"Not watching", :dismissed}
    ]
  end

  @doc "How long the recording is, in words."
  defdelegate runtime(edition), to: Ambry.Wanted.Edition

  @doc false
  def credited(names), do: Enum.map(names, &%{name: &1})

  @doc "What to call the provider a record came from."
  defdelegate provider_words(provider_id), to: Ambry.Wanted, as: :provider_name

  @doc false
  def statuses, do: Watch.statuses()
end
