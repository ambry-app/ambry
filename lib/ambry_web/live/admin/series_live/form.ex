defmodule AmbryWeb.Admin.SeriesLive.Form do
  @moduledoc false
  use AmbryWeb, :admin_live_view

  alias Ambry.Books
  alias Ambry.Series
  alias Ecto.Changeset

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    {:ok, assign(socket, books: Books.for_select())}
  end

  @impl Phoenix.LiveView
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    series = Series.get_series!(id)
    changeset = Series.change_series(series)

    socket
    |> assign_form(changeset)
    |> assign(
      page_title: series.name,
      series: series
    )
  end

  defp apply_action(socket, :new, _params) do
    series = %Series.Series{}
    changeset = Series.change_series(series)

    socket
    |> assign_form(changeset)
    |> assign(
      page_title: "New Series",
      series: series
    )
  end

  @impl Phoenix.LiveView
  def handle_event("validate", %{"series" => series_params}, socket) do
    changeset =
      socket.assigns.series
      |> Series.change_series(series_params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("submit", %{"series" => series_params}, socket) do
    save_series(socket, socket.assigns.live_action, series_params)
  end

  defp save_series(socket, :edit, series_params) do
    case Series.update_series(socket.assigns.series, series_params) do
      {:ok, series} ->
        {:noreply,
         socket
         |> put_flash(:info, "Updated #{series.name}")
         |> push_navigate(to: ~p"/admin/series")}

      {:error, %Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save_series(socket, :new, series_params) do
    case Series.create_series(series_params) do
      {:ok, series} ->
        {:noreply,
         socket
         |> put_flash(:info, "Created #{series.name}")
         |> push_navigate(to: ~p"/admin/series")}

      {:error, %Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp assign_form(socket, %Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset))
  end
end
