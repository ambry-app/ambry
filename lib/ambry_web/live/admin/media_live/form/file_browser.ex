defmodule AmbryWeb.Admin.MediaLive.Form.FileBrowser do
  @moduledoc false

  use AmbryWeb, :live_component

  @allowed_extensions ~w(.mp3 .mp4 .m4a .m4b .opus)

  @impl Phoenix.LiveComponent
  def render(assigns) do
    ~H"""
    <div class="space-y-2">
      <div class="flex gap-2">
        <span><%= MapSet.size(@selected_files) %> file(s) selected</span>
        <.brand_link phx-click="clear" phx-target={@myself}>clear</.brand_link>
      </div>
      <hr />
      <.display_path path={@current_path} root={@root_path} />
      <hr />
      <div class="flex gap-2">
        <.brand_link phx-click="go-up" phx-target={@myself}>go up</.brand_link>
        <.brand_link phx-click="select-all" phx-target={@myself}>select all</.brand_link>
        <.brand_link phx-click="deselect-all" phx-target={@myself}>de-select all</.brand_link>
      </div>
      <hr />
      <ul>
        <li :for={%{path: file, stat: stat} <- full_ls!(@current_path)} class="font-mono flex min-w-0 gap-2">
          <%= if stat.type == :directory do %>
            <div class="w-4 flex-none" />
            <%!-- FIXME: security --%>
            <div class="grow overflow-hidden text-ellipsis whitespace-nowrap">
              <.brand_link phx-click={JS.push("select-directory", value: %{dir: file})} phx-target={@myself}>
                <%= Path.basename(file) %>
              </.brand_link>
            </div>
          <% else %>
            <%= if Path.extname(file) in @allowed_extensions do %>
              <div class="w-4">
                <%!-- FIXME: security --%>
                <input
                  type="checkbox"
                  checked={MapSet.member?(@selected_files, file)}
                  phx-click={JS.push("toggle-file", value: %{file: file})}
                  phx-target={@myself}
                />
              </div>
              <div class="grow overflow-hidden text-ellipsis whitespace-nowrap"><%= Path.basename(file) %></div>
            <% else %>
              <div class="w-4" />
              <div class="grow overflow-hidden text-ellipsis whitespace-nowrap text-slate-600">
                <%= Path.basename(file) %>
              </div>
            <% end %>
          <% end %>
          <div class="w-48 flex-none text-right text-sm italic text-zinc-500">
            <%= stat.mtime |> NaiveDateTime.from_erl!() |> Calendar.strftime("%c") %>
          </div>
        </li>
      </ul>
      <.button phx-click="confirm-selection" phx-target={@myself}>Select Files</.button>
    </div>
    """
  end

  defp files_only!(path) do
    path
    |> full_ls!()
    |> Enum.filter(&(&1.stat.type != :directory))
  end

  def full_ls!(path) do
    path
    |> File.ls!()
    |> Enum.map(fn file ->
      full_path = Path.join(path, file)

      %{
        path: full_path,
        stat: File.stat!(full_path)
      }
    end)
    |> Enum.sort_by(& &1.stat.mtime, :desc)
  end

  @impl Phoenix.LiveComponent
  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign_new(:allowed_extensions, fn -> @allowed_extensions end)
      |> assign_new(:selected_files, fn -> MapSet.new() end)
      |> assign_new(:current_path, fn -> assigns.root_path end)

    {:ok, socket}
  end

  @impl Phoenix.LiveComponent
  def handle_event("select-directory", %{"dir" => dir}, socket) do
    {:noreply, assign(socket, current_path: dir)}
  end

  def handle_event("toggle-file", %{"file" => file}, socket) do
    selected_files = socket.assigns.selected_files
    allowed_extensions = socket.assigns.allowed_extensions

    {selected_files, allowed_extensions} =
      if MapSet.member?(selected_files, file) do
        deselect_files(selected_files, [file], allowed_extensions)
      else
        select_files(selected_files, [file], allowed_extensions)
      end

    {:noreply,
     assign(socket, selected_files: selected_files, allowed_extensions: allowed_extensions)}
  end

  def handle_event("select-all", _params, socket) do
    files_to_select = files_only!(socket.assigns.current_path)

    {selected_files, allowed_extensions} =
      select_files(
        socket.assigns.selected_files,
        files_to_select,
        socket.assigns.allowed_extensions
      )

    {:noreply,
     assign(socket, selected_files: selected_files, allowed_extensions: allowed_extensions)}
  end

  def handle_event("deselect-all", _params, socket) do
    files_to_deselect = files_only!(socket.assigns.current_path)

    {selected_files, allowed_extensions} =
      deselect_files(
        socket.assigns.selected_files,
        files_to_deselect,
        socket.assigns.allowed_extensions
      )

    {:noreply,
     assign(socket, selected_files: selected_files, allowed_extensions: allowed_extensions)}
  end

  def handle_event("clear", _params, socket) do
    {:noreply,
     assign(socket, selected_files: MapSet.new(), allowed_extensions: @allowed_extensions)}
  end

  def handle_event("go-up", _params, socket) do
    up =
      if socket.assigns.root_path != socket.assigns.current_path do
        Path.dirname(socket.assigns.current_path)
      else
        socket.assigns.current_path
      end

    {:noreply, assign(socket, current_path: up)}
  end

  def handle_event("confirm-selection", _params, socket) do
    send(self(), {:files_selected, socket.assigns.selected_files})

    {:noreply, socket}
  end

  def handle_event("toggle-hidden", _params, socket) do
    {:noreply, assign(socket, show_hidden: !socket.assigns.show_hidden)}
  end

  defp deselect_files(selected_files, files, allowed_extensions) do
    files_to_deselect = MapSet.new(files)
    selected_files = MapSet.difference(selected_files, files_to_deselect)

    allowed_extensions =
      if Enum.empty?(selected_files) do
        @allowed_extensions
      else
        allowed_extensions
      end

    {selected_files, allowed_extensions}
  end

  defp select_files(selected_files, files, allowed_extensions) do
    case Enum.find(files, &(Path.extname(&1) in allowed_extensions)) do
      nil ->
        {selected_files, allowed_extensions}

      first_file ->
        allowed_extensions = [Path.extname(first_file)]

        files_to_select =
          files |> Enum.filter(&(Path.extname(&1) in allowed_extensions)) |> MapSet.new()

        selected_files = MapSet.union(selected_files, files_to_select)

        {selected_files, allowed_extensions}
    end
  end

  defp display_path(assigns) do
    ~H"""
    <%= if @path == @root do %>
      <p>/</p>
    <% else %>
      <p><%= String.slice(@path, String.length(@root)..-1//1) %></p>
    <% end %>
    """
  end
end
