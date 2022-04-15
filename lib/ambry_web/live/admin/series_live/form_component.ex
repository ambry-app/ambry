defmodule AmbryWeb.Admin.SeriesLive.FormComponent do
  @moduledoc false

  use AmbryWeb, :live_component

  import AmbryWeb.Admin.ParamHelpers, only: [map_to_list: 2]

  alias Ambry.{Books, Series}

  @impl Phoenix.LiveComponent
  def mount(socket) do
    {:ok, assign(socket, :books, books())}
  end

  @impl Phoenix.LiveComponent
  def update(%{series: series} = assigns, socket) do
    changeset = Series.change_series(series, init_series_param(series))

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:changeset, changeset)}
  end

  @impl Phoenix.LiveComponent
  def handle_event("validate", %{"series" => series_params}, socket) do
    series_params = clean_series_params(series_params)

    changeset =
      socket.assigns.series
      |> Series.change_series(series_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :changeset, changeset)}
  end

  def handle_event("save", %{"series" => series_params}, socket) do
    save_series(socket, socket.assigns.action, series_params)
  end

  def handle_event("add-book", _params, socket) do
    params =
      socket.assigns.changeset.params
      |> map_to_list("series_books")
      |> Map.update!("series_books", fn series_books_params ->
        series_books_params ++ [%{}]
      end)

    changeset = Series.change_series(socket.assigns.series, params)

    {:noreply, assign(socket, :changeset, changeset)}
  end

  defp clean_series_params(params) do
    params
    |> map_to_list("series_books")
    |> Map.update!("series_books", fn series_books ->
      Enum.reject(series_books, fn series_book_params ->
        is_nil(series_book_params["id"]) && series_book_params["delete"] == "true"
      end)
    end)
  end

  defp save_series(socket, :edit, series_params) do
    case Series.update_series(socket.assigns.series, series_params) do
      {:ok, _series} ->
        {:noreply,
         socket
         |> put_flash(:info, "Series updated successfully")
         |> push_redirect(to: socket.assigns.return_to)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :changeset, changeset)}
    end
  end

  defp save_series(socket, :new, series_params) do
    case Series.create_series(series_params) do
      {:ok, _series} ->
        {:noreply,
         socket
         |> put_flash(:info, "Series created successfully")
         |> push_redirect(to: socket.assigns.return_to)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, changeset: changeset)}
    end
  end

  defp books do
    Books.for_select()
  end

  defp init_series_param(series) do
    %{
      "series_books" => Enum.map(series.series_books, &%{"id" => &1.id})
    }
  end
end
