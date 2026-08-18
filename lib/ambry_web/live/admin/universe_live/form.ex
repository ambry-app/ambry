defmodule AmbryWeb.Admin.UniverseLive.Form do
  @moduledoc false
  use AmbryWeb, :admin_live_view

  alias Ambry.Books
  alias AmbryWeb.Admin.ReturnTo
  alias Ecto.Changeset

  @impl Phoenix.LiveView
  def mount(params, _session, socket) do
    # The list the operator came from, kept so every way out of this form goes
    # back to it. See `AmbryWeb.Admin.ReturnTo`.
    {:ok, assign(socket, list_params: ReturnTo.list_params(params))}
  end

  @impl Phoenix.LiveView
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    universe = Books.get_universe!(id)
    changeset = Books.change_universe(universe)

    socket
    |> assign_form(changeset)
    |> assign(
      page_title: universe.name,
      universe: universe
    )
  end

  defp apply_action(socket, :new, _params) do
    universe = %Books.Universe{}
    changeset = Books.change_universe(universe)

    socket
    |> assign_form(changeset)
    |> assign(
      page_title: "New Universe",
      universe: universe
    )
  end

  @impl Phoenix.LiveView
  def handle_event("validate", %{"universe" => universe_params}, socket) do
    changeset =
      socket.assigns.universe
      |> Books.change_universe(universe_params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("submit", %{"universe" => universe_params}, socket) do
    save_universe(socket, socket.assigns.live_action, universe_params)
  end

  defp save_universe(socket, :edit, universe_params) do
    case Books.update_universe(socket.assigns.universe, universe_params) do
      {:ok, universe} ->
        {:noreply,
         socket
         |> put_flash(:info, "Updated #{universe.name}")
         |> push_navigate(
           to: ReturnTo.path(~p"/admin/universes", socket.assigns.list_params, universe.id)
         )}

      {:error, %Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save_universe(socket, :new, universe_params) do
    case Books.create_universe(universe_params) do
      {:ok, universe} ->
        {:noreply,
         socket
         |> put_flash(:info, "Created #{universe.name}")
         |> push_navigate(
           to: ReturnTo.path(~p"/admin/universes", socket.assigns.list_params, universe.id)
         )}

      {:error, %Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp assign_form(socket, %Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset))
  end
end
