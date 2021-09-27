defmodule AmbryWeb.Admin.PaginationHelpers do
  @moduledoc """
  Helpers for building paginated / filterable lists.
  """

  @limit 10

  def limit do
    @limit
  end

  def get_list_opts(%Phoenix.LiveView.Socket{} = socket) do
    Map.get(socket.assigns, :list_opts, %{page: 1, filter: nil})
  end

  def get_list_opts(%{} = params) do
    page =
      case params |> Map.get("page", "1") |> Integer.parse() do
        {page, _} when page >= 1 -> page
        {_bad_page, _} -> 1
        :error -> 1
      end

    filter =
      case params |> Map.get("filter", "") |> String.trim() do
        "" -> nil
        filter -> filter
      end

    %{
      page: page,
      filter: filter
    }
  end

  def page_to_offset(page) do
    page * @limit - @limit
  end

  def prev_opts(list_opts) do
    list_opts
    |> Map.update!(:page, &(&1 - 1))
    |> patch_opts()
  end

  def next_opts(list_opts) do
    list_opts
    |> Map.update!(:page, &(&1 + 1))
    |> patch_opts()
  end

  def patch_opts(list_opts) do
    list_opts
    |> Enum.filter(fn
      {:page, 1} -> false
      {_key, nil} -> false
      _else -> true
    end)
    |> Map.new()
  end
end
