defmodule AmbryWeb.Admin.MediaLive.FileStatRow do
  @moduledoc """
  Renders a row for a file in the file stats table.
  """

  use AmbryWeb, :component

  prop label, :string, required: true
  prop file, :any, required: true
  prop error_type, :atom, default: :error

  def render(assigns) do
    ~F"""
    <div class="p-2 flex">
      <div class="pr-2 w-28">
        <span class="px-1 border border-gray-200 rounded-md bg-gray-50">
          {@label}
        </span>
      </div>
      {#if @file}
        <div class="flex-grow break-all pr-2">
          {@file.path}
        </div>
        <div class="flex-shrink">
          {#case @file.stat}
            {#match error when is_atom(error)}
              <span class={"px-1 border rounded-md " <> classes_for_error_type(@error_type)}>
                {error}
              </span>
            {#match stat when is_map(stat)}
              <span class="px-1 border border-blue-200 rounded-md bg-blue-50 whitespace-nowrap">
                {format_filesize(stat.size)}
              </span>
          {/case}
        </div>
      {#else}
        <div class="flex-grow" />
        <div class="flex-shrink">
          <span class="px-1 border border-red-200 rounded-md bg-red-50">
            nil
          </span>
        </div>
      {/if}
    </div>
    """
  end

  defp classes_for_error_type(:error), do: "border-red-200 bg-red-50"
  defp classes_for_error_type(:warn), do: "border-yellow-200 bg-yellow-50"

  defp format_filesize(bytes) do
    bytes |> FileSize.from_bytes() |> FileSize.scale() |> FileSize.format()
  end
end
