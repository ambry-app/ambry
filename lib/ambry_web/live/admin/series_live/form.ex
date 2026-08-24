defmodule AmbryWeb.Admin.SeriesLive.Form do
  @moduledoc false
  use AmbryWeb, :admin_live_view

  alias Ambry.Books
  alias AmbryWeb.Admin.Deletion
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
    series = Books.get_series!(id)
    changeset = Books.change_series(series)

    socket
    |> assign_form(changeset)
    |> assign(
      page_title: series.name,
      series: series
    )
  end

  defp apply_action(socket, :new, _params) do
    series = %Books.Series{}
    changeset = Books.change_series(series)

    socket
    |> assign_form(changeset)
    |> assign(
      page_title: "New Series",
      series: series
    )
  end

  @impl Phoenix.LiveView
  def handle_event("delete", _params, socket) do
    case Deletion.outcome(Books.delete_series(socket.assigns.series), socket.assigns.series.name) do
      {:ok, message} ->
        {:noreply,
         socket
         |> put_flash(:info, message)
         |> push_navigate(to: ReturnTo.path(~p"/admin/series", socket.assigns.list_params))}

      {:error, message} ->
        {:noreply, put_flash(socket, :error, message)}
    end
  end

  def handle_event("validate", %{"series" => series_params}, socket) do
    changeset =
      socket.assigns.series
      |> Books.change_series(series_params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("submit", %{"series" => series_params}, socket) do
    save_series(socket, socket.assigns.live_action, series_params)
  end

  defp save_series(socket, :edit, series_params) do
    case Books.update_series(socket.assigns.series, series_params) do
      {:ok, series} ->
        {:noreply,
         socket
         |> put_flash(:info, "Updated #{series.name}")
         |> push_navigate(
           to: ReturnTo.path(~p"/admin/series", socket.assigns.list_params, series.id)
         )}

      {:error, %Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save_series(socket, :new, series_params) do
    case Books.create_series(series_params) do
      {:ok, series} ->
        {:noreply,
         socket
         |> put_flash(:info, "Created #{series.name}")
         |> push_navigate(
           to: ReturnTo.path(~p"/admin/series", socket.assigns.list_params, series.id)
         )}

      {:error, %Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp assign_form(socket, %Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset))
  end
end
