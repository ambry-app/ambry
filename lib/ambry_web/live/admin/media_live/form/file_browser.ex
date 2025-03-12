defmodule AmbryWeb.Admin.MediaLive.Form.FileBrowser do
  @moduledoc false

  use AmbryWeb, :live_component

  @allowed_extensions ~w(.mp3 .mp4 .m4a .m4b .opus)

  @impl Phoenix.LiveComponent
  def render(assigns) do
    ~H"""
    <div class="h-screen p-6">
      <div class="mx-auto flex h-full max-w-3xl flex-col space-y-4">
        <div class="text-2xl font-bold">Import files from server file-system</div>
        <div class="flex-1 overflow-auto border-t border-b border-zinc-200 dark:border-zinc-800">
          <.tree_node
            :for={file_or_folder <- @browser.tree}
            level={0}
            node={file_or_folder}
            open_folders={@open_folders}
            selected_files={@selected_files}
            allowed_extensions={@allowed_extensions}
            target={@myself}
          />
        </div>
        <div class="flex items-center gap-2">
          <.button color={:brand} phx-click="confirm-selection" phx-target={@myself}>Select Files</.button>
          <div class="grow">{MapSet.size(@selected_files)} file(s) selected</div>
          <.button color={:zinc} phx-click="clear" phx-target={@myself}>Clear</.button>
          <.button type="button" color={:zinc} phx-click={JS.exec("data-cancel", to: "#select-files-modal")}>
            Cancel
          </.button>
        </div>
      </div>
    </div>
    <%!-- <div class="mx-auto max-w-3xl space-y-4">
      <div class="text-2xl font-bold">Import files from server file-system</div>

      <div class="space-y-1">
        <.tree_node
          :for={file_or_folder <- @browser.tree}
          level={0}
          node={file_or_folder}
          open_folders={@open_folders}
          selected_files={@selected_files}
          allowed_extensions={@allowed_extensions}
          target={@myself}
        />
      </div>

      <div class="flex items-center gap-2">
        <.button color={:brand} phx-click="confirm-selection" phx-target={@myself}>Select Files</.button>
        <div class="grow">{MapSet.size(@selected_files)} file(s) selected</div>
        <.button color={:zinc} phx-click="clear" phx-target={@myself}>Clear</.button>
        <.button type="button" color={:zinc} phx-click={JS.exec("data-cancel", to: "#select-files-modal")}>
          Cancel
        </.button>
      </div>
    </div> --%>
    """
  end

  @impl Phoenix.LiveComponent
  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign_new(:allowed_extensions, fn -> @allowed_extensions end)
      |> assign_new(:selected_files, fn -> MapSet.new() end)
      |> assign_new(:open_folders, fn -> MapSet.new() end)
      |> assign_new(:current_path, fn -> assigns.root_path end)
      |> assign_new(:browser, fn -> Ambry.FileBrowser.new(assigns.root_path) end)

    {:ok, socket}
  end

  @impl Phoenix.LiveComponent
  def handle_event("toggle-folder", %{"id" => id}, socket) do
    if MapSet.member?(socket.assigns.open_folders, id) do
      {:noreply, update(socket, :open_folders, fn folders -> MapSet.delete(folders, id) end)}
    else
      {:noreply,
       socket
       |> update(:browser, fn browser -> Ambry.FileBrowser.load_contents(browser, id) end)
       |> update(:open_folders, fn folders -> MapSet.put(folders, id) end)}
    end
  end

  def handle_event("toggle-file", %{"id" => id}, socket) do
    browser = socket.assigns.browser
    selected_files = socket.assigns.selected_files
    allowed_extensions = socket.assigns.allowed_extensions

    {selected_files, allowed_extensions} =
      if MapSet.member?(selected_files, id) do
        {:ok, file} = Ambry.FileBrowser.fetch_file(browser, id)
        deselect_files(selected_files, [file], allowed_extensions)
      else
        {:ok, file} = Ambry.FileBrowser.fetch_file(browser, id)
        select_files(selected_files, [file], allowed_extensions)
      end

    {:noreply,
     assign(socket, selected_files: selected_files, allowed_extensions: allowed_extensions)}
  end

  def handle_event("select-all", %{"id" => id}, socket) do
    browser = socket.assigns.browser
    {:ok, files_to_select} = Ambry.FileBrowser.fetch_files(browser, id)

    {selected_files, allowed_extensions} =
      select_files(
        socket.assigns.selected_files,
        files_to_select,
        socket.assigns.allowed_extensions
      )

    {:noreply,
     assign(socket, selected_files: selected_files, allowed_extensions: allowed_extensions)}
  end

  def handle_event("deselect-all", %{"id" => id}, socket) do
    browser = socket.assigns.browser
    {:ok, files_to_deselect} = Ambry.FileBrowser.fetch_files(browser, id)

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
      if socket.assigns.root_path == socket.assigns.current_path do
        socket.assigns.current_path
      else
        Path.dirname(socket.assigns.current_path)
      end

    {:noreply, assign(socket, current_path: up)}
  end

  def handle_event("confirm-selection", _params, socket) do
    files =
      Enum.map(socket.assigns.selected_files, fn id ->
        {:ok, file} = Ambry.FileBrowser.fetch_file(socket.assigns.browser, id)
        file.full_path
      end)

    send(self(), {:files_selected, files})

    {:noreply, socket}
  end

  def handle_event("toggle-hidden", _params, socket) do
    {:noreply, assign(socket, show_hidden: !socket.assigns.show_hidden)}
  end

  defp deselect_files(selected_files, files, allowed_extensions) do
    files_to_deselect = MapSet.new(files, & &1.id)
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
    case Enum.find(files, &(&1.extension in allowed_extensions)) do
      nil ->
        {selected_files, allowed_extensions}

      first_file ->
        allowed_extensions = [first_file.extension]

        files_to_select =
          files |> Enum.filter(&(&1.extension in allowed_extensions)) |> MapSet.new(& &1.id)

        selected_files = MapSet.union(selected_files, files_to_select)

        {selected_files, allowed_extensions}
    end
  end

  defp any_files?(files_and_folders, allowed_extensions) do
    Enum.count(files_and_folders, fn
      %Ambry.FileBrowser.File{} = file -> file.extension in allowed_extensions
      _ -> false
    end) > 1
  end

  defp all_selected?(files_and_folders, selected_files, allowed_extensions) do
    files_and_folders
    |> Enum.filter(fn
      %Ambry.FileBrowser.File{} = file -> file.extension in allowed_extensions
      _ -> false
    end)
    |> Enum.all?(&MapSet.member?(selected_files, &1.id))
  end

  defp tree_node(%{node: %Ambry.FileBrowser.FolderNode{}} = assigns) do
    ~H"""
    <.folder_node
      level={@level}
      folder_node={@node}
      open_folders={@open_folders}
      selected_files={@selected_files}
      allowed_extensions={@allowed_extensions}
      target={@target}
    />
    """
  end

  defp tree_node(%{node: %Ambry.FileBrowser.File{}} = assigns) do
    ~H"""
    <.file_node
      level={@level}
      file={@node}
      selected_files={@selected_files}
      allowed_extensions={@allowed_extensions}
      target={@target}
    />
    """
  end

  defp folder_node(assigns) do
    ~H"""
    <%= if MapSet.member?(@open_folders, @folder_node.folder.id) do %>
      <.open_folder_node
        level={@level}
        folder_node={@folder_node}
        open_folders={@open_folders}
        selected_files={@selected_files}
        allowed_extensions={@allowed_extensions}
        target={@target}
      />
    <% else %>
      <.closed_folder_node
        level={@level}
        folder_node={@folder_node}
        open_folders={@open_folders}
        selected_files={@selected_files}
        allowed_extensions={@allowed_extensions}
        target={@target}
      />
    <% end %>
    """
  end

  defp open_folder_node(assigns) do
    ~H"""
    <.row level={@level} phx-click={JS.push("toggle-folder", value: %{id: @folder_node.folder.id})} phx-target={@target}>
      <div class="w-4 flex-none"><FA.icon name="folder-minus" class="fill-brand h-4 w-4 dark:fill-brand-dark" /></div>
      <.filename title={@folder_node.folder.path}>{@folder_node.folder.path}</.filename>
      <.mtime timestamp={@folder_node.folder.mtime} />
    </.row>
    <%= if any_files?(@folder_node.children, @allowed_extensions) do %>
      <%= if all_selected?(@folder_node.children, @selected_files, @allowed_extensions) do %>
        <.row
          level={@level + 1}
          phx-click={JS.push("deselect-all", value: %{id: @folder_node.folder.id})}
          phx-target={@target}
        >
          <div class="w-4 flex-none"><input type="checkbox" checked /></div>
          <.filename>{"All"}</.filename>
        </.row>
      <% else %>
        <.row
          level={@level + 1}
          phx-click={JS.push("select-all", value: %{id: @folder_node.folder.id})}
          phx-target={@target}
        >
          <div class="w-4 flex-none"><input type="checkbox" /></div>
          <.filename>{"All"}</.filename>
        </.row>
      <% end %>
    <% end %>
    <.tree_node
      :for={file_or_folder <- @folder_node.children}
      level={@level + 1}
      node={file_or_folder}
      open_folders={@open_folders}
      selected_files={@selected_files}
      allowed_extensions={@allowed_extensions}
      target={@target}
    />
    """
  end

  defp closed_folder_node(assigns) do
    ~H"""
    <.row level={@level} phx-click={JS.push("toggle-folder", value: %{id: @folder_node.folder.id})} phx-target={@target}>
      <div class="w-4 flex-none"><FA.icon name="folder-plus" class="fill-brand h-4 w-4 dark:fill-brand-dark" /></div>
      <.filename title={@folder_node.folder.path}>{@folder_node.folder.path}</.filename>
      <.mtime timestamp={@folder_node.folder.mtime} />
    </.row>
    """
  end

  defp file_node(assigns) do
    ~H"""
    <%= if @file.extension in @allowed_extensions do %>
      <.allowed_file_node level={@level} file={@file} selected_files={@selected_files} target={@target} />
    <% else %>
      <.disallowed_file_node level={@level} file={@file} />
    <% end %>
    """
  end

  defp allowed_file_node(assigns) do
    ~H"""
    <.row level={@level} phx-click={JS.push("toggle-file", value: %{id: @file.id})} phx-target={@target} class="font-bold">
      <div class="w-4 flex-none"><input type="checkbox" checked={MapSet.member?(@selected_files, @file.id)} /></div>
      <.filename title={@file.path}>{@file.path}</.filename>
      <.mtime timestamp={@file.mtime} />
    </.row>
    """
  end

  defp disallowed_file_node(assigns) do
    ~H"""
    <.row level={@level} class="italic text-slate-600">
      <div class="w-4 flex-none" />
      <.filename title={@file.path}>{@file.path}</.filename>
      <.mtime timestamp={@file.mtime} />
    </.row>
    """
  end

  attr :level, :integer, required: true
  attr :class, :string, default: nil
  attr :rest, :global

  slot :inner_block, required: true

  defp row(assigns) do
    ~H"""
    <div class={["font-mono flex min-w-0 cursor-pointer items-center gap-2 hover:underline", @class]} {@rest}>
      <.spacer :if={@level > 0} level={@level} />
      {render_slot(@inner_block)}
    </div>
    """
  end

  attr :class, :string, default: nil
  attr :rest, :global

  slot :inner_block, required: true

  defp filename(assigns) do
    ~H"""
    <div class={["grow overflow-hidden text-ellipsis whitespace-nowrap", @class]} {@rest}>
      {render_slot(@inner_block)}
    </div>
    """
  end

  attr :timestamp, NaiveDateTime, required: true

  defp mtime(assigns) do
    ~H"""
    <div class="w-48 flex-none text-right text-sm italic text-zinc-500">
      {@timestamp |> Calendar.strftime("%c")}
    </div>
    """
  end

  attr :level, :integer, required: true

  defp spacer(assigns) do
    ~H"""
    <div class="flex-none" style={"width: #{(@level * 16) + ((@level - 1) * 8)}px;"} />
    """
  end
end
