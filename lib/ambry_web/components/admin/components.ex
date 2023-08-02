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
          <.link navigate={@new_path} class="flex items-center font-bold text-lime-500 hover:underline dark:text-lime-400">
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
    <div class="rounded-sm border border-zinc-200 bg-zinc-50 dark:border-zinc-800 dark:bg-zinc-900">
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
    <span class={["whitespace-nowrap rounded-sm border px-1 text-zinc-900", badge_color(@color)]}>
      <%= render_slot(@inner_block) %>
    </span>
    """
  end

  defp badge_color(:yellow), do: "border-yellow-200 bg-yellow-50 dark:border-yellow-400 dark:bg-yellow-400"
  defp badge_color(:blue), do: "border-blue-200 bg-blue-50 dark:border-blue-400 dark:bg-blue-400"
  defp badge_color(:red), do: "border-red-200 bg-red-50 dark:border-red-400 dark:bg-red-400"
  defp badge_color(:brand), do: "border-lime-200 bg-lime-50 dark:border-lime-400 dark:bg-lime-400"
  defp badge_color(:gray), do: "border-zinc-200 bg-zinc-100 dark:border-zinc-400 dark:bg-zinc-400"

  attr :drop_param, :atom, required: true
  attr :parent_form, Form, required: true
  attr :form, Form, required: true
  attr :class, :string, default: nil, doc: "class overrides"

  def delete_button(assigns) do
    ~H"""
    <label class={["flex", @class]}>
      <input type="checkbox" name={@parent_form[@drop_param].name <> "[]"} value={@form.index} class="hidden" />
      <FA.icon name="trash" class="h-4 w-4 cursor-pointer fill-current transition-colors hover:text-red-600" />
    </label>
    """
  end

  attr :drop_param, :atom, required: true
  attr :form, Form, required: true

  def delete_input(assigns) do
    ~H"""
    <input type="hidden" name={@form[@drop_param].name <> "[]"} />
    """
  end

  attr :sort_param, :atom, required: true
  attr :parent_form, Form, required: true
  attr :form, Form, required: true

  def sort_input(assigns) do
    ~H"""
    <input type="hidden" name={@parent_form[@sort_param].name <> "[]"} value={@form.index} />
    """
  end

  attr :sort_param, :atom, required: true
  attr :form, Form, required: true
  attr :label, :string, required: true

  def add_button(assigns) do
    ~H"""
    <label class="text-brand flex cursor-pointer items-center gap-1 hover:underline dark:text-brand-dark">
      <input type="checkbox" name={@form[@sort_param].name <> "[]"} class="hidden" /> <%= @label %>
      <FA.icon name="plus" class="h-4 w-4 fill-current" />
    </label>
    """
  end

  attr :field, FormField, required: true
  attr :label, :string, required: true
  slot :inner_block, required: true

  def import_form_row(assigns) do
    ~H"""
    <div class="flex gap-4 rounded-sm p-3 hover:bg-zinc-950">
      <div class="py-1">
        <.input type="checkbox" field={@field} />
      </div>
      <label for={@field.id} class="grow cursor-pointer space-y-2">
        <span class="text-sm font-semibold leading-6 text-zinc-800 dark:text-zinc-200">
          <%= @label %>
        </span>
        <%= render_slot(@inner_block) %>
      </label>
    </div>
    """
  end

  @doc """
  Book Card for displaying scraping results from GoodReads, Audible, etc.
  """
  attr :book, :any, required: true
  slot :actions

  def book_card(%{book: %AmbryScraping.GoodReads.Books.Search.Book{}} = assigns) do
    ~H"""
    <div class="flex gap-2 text-sm">
      <img src={@book.thumbnail.data_url} class="object-contain object-top" />
      <div>
        <p class="font-bold"><%= @book.title %></p>
        <p class="text-zinc-400">
          by
          <span :for={contributor <- @book.contributors} class="group">
            <span><%= contributor.name %></span>
            <span class="text-xs text-zinc-600">(<%= contributor.type %>)</span>
            <br class="group-last:hidden" />
          </span>
        </p>
        <div :for={action <- @actions}>
          <%= render_slot(action) %>
        </div>
      </div>
    </div>
    """
  end

  def book_card(%{book: %AmbryScraping.GoodReads.Books.Editions.Edition{}} = assigns) do
    ~H"""
    <div class="flex gap-2 text-sm">
      <img src={@book.thumbnail.data_url} class="object-contain object-top" />
      <div>
        <p class="font-bold"><%= @book.title %></p>
        <p class="text-zinc-400">
          by
          <span :for={contributor <- @book.contributors} class="group">
            <span><%= contributor.name %></span>
            <span class="text-xs text-zinc-600">(<%= contributor.type %>)</span>
            <br class="group-last:hidden" />
          </span>
        </p>
        <p :if={@book.published && @book.publisher} class="text-xs text-zinc-400">
          Published <%= display_date(@book.published) %> by <%= @book.publisher %>
        </p>
        <p class="text-xs text-zinc-400"><%= @book.format %></p>
        <div :for={action <- @actions}>
          <%= render_slot(action) %>
        </div>
      </div>
    </div>
    """
  end

  def book_card(%{book: %AmbryScraping.Audible.Products.Product{}} = assigns) do
    ~H"""
    <div class="flex gap-2 text-sm">
      <img src={@book.cover_image.src} class="h-24 w-24" />
      <div>
        <p class="font-bold"><%= @book.title %></p>
        <p :if={@book.authors != []} class="text-zinc-400">
          by
          <span :for={author <- @book.authors} class="group">
            <span><%= author.name %></span>
            <br class="group-last:hidden" />
          </span>
        </p>
        <p :if={@book.narrators != []} class="text-zinc-400">
          Narrated by
          <span :for={narrator <- @book.narrators} class="group">
            <span><%= narrator.name %></span>
            <br class="group-last:hidden" />
          </span>
        </p>
        <p :if={@book.published && @book.publisher} class="text-xs text-zinc-400">
          Published <%= display_date(@book.published) %> by <%= @book.publisher %>
        </p>
        <p class="text-xs text-zinc-400"><%= @book.format %></p>
        <div :for={action <- @actions}>
          <%= render_slot(action) %>
        </div>
      </div>
    </div>
    """
  end

  def display_date(%Date{} = date), do: Calendar.strftime(date, "%B %-d, %Y")

  def display_date(%AmbryScraping.GoodReads.PublishedDate{display_format: :full, date: date}),
    do: Calendar.strftime(date, "%B %-d, %Y")

  def display_date(%AmbryScraping.GoodReads.PublishedDate{display_format: :year_month, date: date}),
    do: Calendar.strftime(date, "%B %Y")

  def display_date(%AmbryScraping.GoodReads.PublishedDate{display_format: :year, date: date}),
    do: Calendar.strftime(date, "%Y")
end
