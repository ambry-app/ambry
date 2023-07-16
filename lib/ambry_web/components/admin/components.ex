defmodule AmbryWeb.Admin.Components do
  @moduledoc false

  use AmbryWeb, :html

  alias Phoenix.HTML.Form
  alias Phoenix.HTML.FormField

  def admin_table_header(assigns) do
    ~H"""
    <div class="flex items-center">
      <.admin_table_search_form filter={@list_opts.filter} />
      <div class="flex-grow" />
      <%= if @new_path do %>
        <div class="px-2">
          <.link patch={@new_path} class="flex items-center font-bold text-lime-500 hover:underline dark:text-lime-400">
            New <FA.icon name="plus" class="ml-2 h-4 w-4 fill-current" />
          </.link>
        </div>
      <% end %>
      <div class="px-2">
        <.pagination_chevron active={@list_opts.page > 1} name="chevron-left" to={@prev_page} />
      </div>
      <div class="px-2">
        <.pagination_chevron active={@has_more} name="chevron-right" to={@next_page} />
      </div>
    </div>
    """
  end

  defp admin_table_search_form(assigns) do
    ~H"""
    <.form for={%{}} as={:search} phx-submit="search">
      <input
        id="searchInput"
        type="search"
        name="search[query]"
        value={@filter}
        placeholder="Search"
        class="mb-2 w-full border-0 border-b border-zinc-200 bg-transparent px-0 placeholder:font-bold placeholder:text-zinc-500 focus:border-0 focus:border-b focus:border-lime-500 focus:outline-none focus:ring-0 dark:border-zinc-800 dark:focus:border-lime-400"
      />
    </.form>
    """
  end

  defp pagination_chevron(assigns) do
    ~H"""
    <%= if @active do %>
      <.link patch={@to} class="cursor-pointer">
        <FA.icon
          name={@name}
          class="h-5 w-5 fill-current text-zinc-600 hover:text-zinc-900 dark:text-zinc-500 dark:hover:text-zinc-100"
        />
      </.link>
    <% else %>
      <FA.icon name={@name} class="h-5 w-5 fill-current dark:text-zinc-900" />
    <% end %>
    """
  end

  def admin_table(assigns) do
    assigns = assign_new(assigns, :row_click, fn -> true end)

    default_cell_class = if assigns.row_click, do: "p-3 text-left cursor-pointer", else: "p-3 text-left"

    default_header_class = "p-3 text-left"

    row_class =
      if assigns.row_click,
        do: "border-t border-zinc-200 hover:bg-zinc-200 dark:border-zinc-800 dark:hover:bg-zinc-700",
        else: "border-t border-zinc-200 dark:border-zinc-800"

    assigns =
      assign(assigns,
        default_cell_class: default_cell_class,
        default_header_class: default_header_class,
        row_class: row_class
      )

    ~H"""
    <div class="rounded-md border border-zinc-200 bg-zinc-50 dark:border-zinc-800 dark:bg-zinc-900">
      <%= if @rows == [] do %>
        <div class="p-3">
          <%= render_slot(@no_results) %>
        </div>
      <% else %>
        <table class="w-full">
          <thead>
            <tr>
              <%= for col <- @col do %>
                <th class={[col[:class], @default_header_class]}><%= col.label %></th>
              <% end %>

              <%= if assigns[:actions] do %>
                <th class={[assigns[:actions_class], @default_header_class]} />
              <% end %>
            </tr>
          </thead>
          <tbody>
            <%= for row <- @rows do %>
              <tr class={@row_class}>
                <%= for col <- @col do %>
                  <%= if @row_click do %>
                    <td class={[col[:class], @default_cell_class]} phx-click="row-click" phx-value-id={row.id}>
                      <%= render_slot(col, row) %>
                    </td>
                  <% else %>
                    <td class={[col[:class], @default_cell_class]}>
                      <%= render_slot(col, row) %>
                    </td>
                  <% end %>
                <% end %>

                <%= if assigns[:actions] do %>
                  <td class={[assigns[:actions_class], @default_cell_class]}>
                    <%= render_slot(@actions, row) %>
                  </td>
                <% end %>
              </tr>
            <% end %>
          </tbody>
        </table>
      <% end %>
    </div>
    """
  end

  @doc """
  Renders a colored badge with a label in it.

  ## Examples

      <.badge color={:red}>Foo</.badge>
  """
  attr :color, :atom, doc: "one of yellow, blue, red, brand, or gray"
  slot :inner_block, required: true

  def badge(assigns) do
    ~H"""
    <span class={["whitespace-nowrap rounded-md border px-1 text-zinc-900", badge_color(@color)]}>
      <%= render_slot(@inner_block) %>
    </span>
    """
  end

  defp badge_color(:yellow), do: "border-yellow-200 bg-yellow-50 dark:border-yellow-400 dark:bg-yellow-400"

  defp badge_color(:blue), do: "border-blue-200 bg-blue-50 dark:border-blue-400 dark:bg-blue-400"
  defp badge_color(:red), do: "border-red-200 bg-red-50 dark:border-red-400 dark:bg-red-400"
  defp badge_color(:brand), do: "border-lime-200 bg-lime-50 dark:border-lime-400 dark:bg-lime-400"
  defp badge_color(:gray), do: "border-zinc-200 bg-zinc-100 dark:border-zinc-400 dark:bg-zinc-400"

  @doc """
  Renders a fancy checkbox disguised as a trash-can icon.

  Requires a `%Phoenix.HTML.FormField{}`.

  ## Examples

      <.delete_checkbox field={@form[:delete]} />
  """
  attr :field, FormField, doc: "a form field struct retrieved from the form, for example: @form[:email]"

  attr :class, :string, default: nil, doc: "class overrides"

  def delete_checkbox(%{field: %FormField{} = field} = assigns) do
    assigns =
      assigns
      |> assign(field: nil, id: field.id)
      |> assign(:name, field.name)
      |> assign(:checked, Form.normalize_value("checkbox", field.value))

    ~H"""
    <label class={["flex", @class]}>
      <input type="checkbox" id={@id} name={@name} value="true" checked={@checked} class="peer hidden" />
      <FA.icon
        name="trash"
        class="h-4 w-4 cursor-pointer fill-current transition-colors hover:text-red-600 peer-checked:text-red-600"
      />
    </label>
    """
  end

  attr :name, :string, required: true
  attr :value, :integer, required: true
  attr :class, :string, default: nil, doc: "class overrides"

  def new_delete_checkbox(assigns) do
    ~H"""
    <label class={["flex", @class]}>
      <input type="checkbox" name={@name} value={@value} class="hidden" />
      <FA.icon name="trash" class="h-4 w-4 cursor-pointer fill-current transition-colors hover:text-red-600" />
    </label>
    """
  end
end
