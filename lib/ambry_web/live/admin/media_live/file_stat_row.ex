defmodule AmbryWeb.Admin.MediaLive.FileStatRow do
  @moduledoc """
  Renders a row for a file in the file stats table.
  """

  use AmbryWeb, :component

  def render(assigns) do
    assigns = assign_new(assigns, :error_type, fn -> :error end)

    ~H"""
    <div class="p-2 flex">
      <div class="pr-2 w-28">
        <Adc.admin_badge label={@label} color="gray" />
      </div>
      <%= if @file do %>
        <div class="grow break-all pr-2">
          <%= @file.path %>
        </div>
        <div class="shrink">
          <%= case @file.stat do %>
            <% error when is_atom(error) -> %>
              <Adc.admin_badge label={error} color={color_for_error_type(@error_type)} />
            <% stat when is_map(stat) -> %>
              <Adc.admin_badge label={format_filesize(stat.size)} color="blue" />
          <% end %>
        </div>
      <% else %>
        <div class="grow" />
        <div class="shrink">
          <Adc.admin_badge label="nil" color="red" />
        </div>
      <% end %>
    </div>
    """
  end

  defp color_for_error_type(:error), do: "red"
  defp color_for_error_type(:warn), do: "yellow"

  defp format_filesize(bytes) do
    bytes |> FileSize.from_bytes() |> FileSize.scale() |> FileSize.format()
  end
end
