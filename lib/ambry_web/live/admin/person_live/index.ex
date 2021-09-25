defmodule AmbryWeb.Admin.PersonLive.Index do
  use AmbryWeb, :live_view

  alias Ambry.People
  alias Ambry.People.Person

  alias AmbryWeb.Admin.PersonLive.FormComponent
  alias AmbryWeb.Components.Modal

  alias Surface.Components.{Form, LivePatch}
  alias Surface.Components.Form.{Field, TextInput}

  @limit 10

  on_mount {AmbryWeb.UserLiveAuth, :ensure_mounted_current_user}
  on_mount {AmbryWeb.Admin.Auth, :ensure_mounted_admin_user}

  @impl true
  def mount(params, _session, socket) do
    {:ok, maybe_update_people(socket, params, true)}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply,
     socket
     |> maybe_update_people(params)
     |> apply_action(socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    socket
    |> assign(:page_title, "Edit Person")
    |> assign(:person, People.get_person!(id))
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "New Person")
    |> assign(:person, %Person{})
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Listing People")
    |> assign(:person, nil)
  end

  defp maybe_update_people(socket, params, force \\ false) do
    old_list_opts = get_list_opts(socket)
    new_list_opts = get_list_opts(params)
    list_opts = Map.merge(old_list_opts, new_list_opts)

    if list_opts != old_list_opts || force do
      {people, has_more?} = list_people(list_opts)

      socket
      |> assign(:list_opts, list_opts)
      |> assign(:has_more?, has_more?)
      |> assign(:people, people)
    else
      socket
    end
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    person = People.get_person!(id)
    {:ok, _} = People.delete_person(person)

    {:noreply, maybe_update_people(socket, %{}, true)}
  end

  def handle_event("search", %{"search" => %{"query" => query}}, socket) do
    socket = maybe_update_people(socket, %{"filter" => query, "page" => "1"})
    list_opts = get_list_opts(socket)

    {:noreply,
     push_patch(socket, to: Routes.admin_person_index_path(socket, :index, patch_opts(list_opts)))}
  end

  defp list_people(opts) do
    People.list_people(page_to_offset(opts.page), @limit, opts.filter)
  end

  defp get_list_opts(%Phoenix.LiveView.Socket{} = socket) do
    Map.get(socket.assigns, :list_opts, %{page: 1, filter: nil})
  end

  defp get_list_opts(%{} = params) do
    page =
      case params |> Map.get("page", "1") |> Integer.parse() do
        {page, _} when page >= 1 -> page
        {_bad_page, _} -> 1
        :error -> 1
      end

    filter =
      case Map.get(params, "filter") do
        nil -> nil
        "" -> nil
        filter -> filter
      end

    %{
      page: page,
      filter: filter
    }
  end

  defp page_to_offset(page) do
    page * @limit - @limit
  end

  defp prev_opts(list_opts) do
    list_opts
    |> Map.update!(:page, &(&1 - 1))
    |> patch_opts()
  end

  defp next_opts(list_opts) do
    list_opts
    |> Map.update!(:page, &(&1 + 1))
    |> patch_opts()
  end

  defp patch_opts(list_opts) do
    list_opts
    |> Enum.filter(fn
      {:page, 1} -> false
      {_key, nil} -> false
      _else -> true
    end)
    |> Map.new()
  end
end
