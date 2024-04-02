defmodule Ambry.FileBrowser do
  @moduledoc """
  Functions for browsing files and directories.
  """

  import File, only: [ls!: 1, stat!: 1]

  alias Ambry.Hashids

  defstruct [:root_path, :tree, :map]

  defmodule FolderNode do
    @moduledoc false
    defstruct [:folder, :children]
  end

  defmodule File do
    @moduledoc false
    defstruct [:id, :path, :full_path, :mtime, :extension, :size]
  end

  defmodule Folder do
    @moduledoc false
    defstruct [:id, :path, :full_path, :mtime]
  end

  def new(root_path) do
    files_and_folders = get_folder_contents(root_path)

    map =
      Map.new(files_and_folders, fn file_or_folder ->
        {file_or_folder.id, file_or_folder}
      end)

    tree =
      Enum.map(files_and_folders, fn
        %File{} = file -> file
        %Folder{} = folder -> %FolderNode{folder: folder, children: :not_loaded}
      end)

    %__MODULE__{
      root_path: root_path,
      tree: tree,
      map: map
    }
  end

  def fetch_file(browser, id) do
    case Map.fetch(browser.map, id) do
      {:ok, %File{} = file} -> {:ok, file}
      {:ok, _not_a_file} -> :error
      :error -> :error
    end
  end

  def fetch_files(browser, id) do
    do_fetch_files(browser.tree, id)
  end

  defp do_fetch_files([], _id), do: :error

  defp do_fetch_files([%FolderNode{folder: %Folder{id: id}} = folder_node | _rest], id) do
    if folder_node.children == :not_loaded do
      :error
    else
      {:ok,
       Enum.filter(folder_node.children, fn
         %File{} -> true
         _ -> false
       end)}
    end
  end

  defp do_fetch_files([%FolderNode{children: [_ | _] = children} | rest], id) do
    case do_fetch_files(children, id) do
      {:ok, files} -> {:ok, files}
      :error -> do_fetch_files(rest, id)
    end
  end

  defp do_fetch_files([_file_or_folder | rest], id), do: do_fetch_files(rest, id)

  def load_contents(browser, folder_id) do
    {tree, added} = do_load_contents(browser.tree, folder_id)

    %{browser | tree: tree, map: Map.merge(browser.map, added)}
  end

  defp do_load_contents(tree, folder_id, result \\ [], added \\ %{})

  defp do_load_contents([], _folder_id, result, added), do: {Enum.reverse(result), added}

  defp do_load_contents(
         [
           %FolderNode{folder: %Folder{id: folder_id} = folder, children: :not_loaded} =
             folder_node
           | rest
         ],
         folder_id,
         result,
         added
       ) do
    files_and_folders = get_folder_contents(folder.full_path)

    map =
      Map.new(files_and_folders, fn file_or_folder ->
        {file_or_folder.id, file_or_folder}
      end)

    tree =
      Enum.map(files_and_folders, fn
        %File{} = file -> file
        %Folder{} = folder -> %FolderNode{folder: folder, children: :not_loaded}
      end)

    folder_node = %{folder_node | children: tree}
    do_load_contents(rest, folder_id, [folder_node | result], Map.merge(added, map))
  end

  defp do_load_contents(
         [%FolderNode{children: [_ | _]} = folder_node | rest],
         folder_id,
         result,
         added
       ) do
    {tree, more_added} = do_load_contents(folder_node.children, folder_id)

    folder_node = %{folder_node | children: tree}
    do_load_contents(rest, folder_id, [folder_node | result], Map.merge(added, more_added))
  end

  defp do_load_contents([file_or_folder | rest], folder_id, result, added),
    do: do_load_contents(rest, folder_id, [file_or_folder | result], added)

  defp get_folder_contents(root_path) do
    root_path
    |> ls!()
    |> Enum.map(fn path ->
      full_path = Path.join(root_path, path)
      stat = stat!(full_path)
      mtime = NaiveDateTime.from_erl!(stat.mtime)
      id = Hashids.encode(stat.inode)

      case stat.type do
        :directory ->
          %Folder{
            id: id,
            path: path,
            full_path: full_path,
            mtime: mtime
          }

        _ ->
          %File{
            id: id,
            path: path,
            full_path: full_path,
            mtime: mtime,
            extension: Path.extname(path),
            size: stat.size |> FileSize.from_bytes() |> FileSize.scale()
          }
      end
    end)
    |> Enum.sort_by(& &1.mtime, {:desc, NaiveDateTime})
  end
end
