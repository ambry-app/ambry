defmodule AmbryWeb.Admin.Components do
  @moduledoc false

  use AmbryWeb, :html

  import AmbryWeb.Gravatar

  alias Ambry.Accounts.User
  alias AmbryScraping.GoodReads.PublishedDate
  alias Phoenix.HTML.Form
  alias Phoenix.HTML.FormField

  attr :user, User, required: true
  attr :title, :string, required: true

  slot :inner_block, required: true
  slot :subheader

  def layout(assigns) do
    ~H"""
    <div class="relative flex h-screen min-w-0 grow flex-col">
      <.layout_header user={@user} title={@title}>
        <%= render_slot(@subheader) %>
      </.layout_header>

      <main class="flex grow flex-col overflow-hidden">
        <div id="main-content" class="grow overflow-y-auto overflow-x-hidden p-4" phx-hook="header-scrollspy">
          <%= render_slot(@inner_block) %>
        </div>
      </main>
    </div>
    """
  end

  attr :user, User, required: true
  attr :title, :string, required: true

  slot :inner_block, required: true

  defp layout_header(assigns) do
    ~H"""
    <header id="nav-header" class="space-y-4 border-zinc-100 p-4 dark:border-zinc-900">
      <div class="flex items-center gap-3">
        <span class="cursor-pointer lg:hidden" phx-click={open_sidebar()}>
          <FA.icon name="bars" class="h-6 w-6 fill-current lg:h-7 lg:w-7" />
        </span>
        <.link navigate={~p"/admin"} class="flex lg:hidden">
          <.logo class="h-6 w-6 lg:h-7 lg:w-7" />
          <.title class="hidden h-6 sm:block lg:h-7" />
        </.link>
        <div class="grow overflow-hidden text-ellipsis whitespace-nowrap pl-0 text-2xl font-bold sm:pl-4 lg:pl-0">
          <%= @title %>
        </div>
        <div
          phx-click-away={hide_menu("admin-user-menu")}
          phx-window-keydown={hide_menu("admin-user-menu")}
          phx-key="escape"
          class="flex-none"
        >
          <img
            phx-click={toggle_menu("admin-user-menu")}
            class="mt-1 h-6 cursor-pointer rounded-full lg:h-7 lg:w-7"
            src={gravatar_url(@user.email)}
          />
          <.admin_menu user={@user} />
        </div>
      </div>
      <%= render_slot(@inner_block) %>
    </header>
    """
  end

  attr :search_form, Form, default: nil
  attr :new_path, :string, default: nil
  attr :has_next, :boolean, default: false
  attr :has_prev, :boolean, default: false
  attr :next_page_path, :string, default: nil
  attr :prev_page_path, :string, default: nil

  slot :inner_block

  def list_controls(assigns) do
    ~H"""
    <div class="flex items-end gap-4">
      <div class="grow">
        <.admin_table_search_form search_form={@search_form} />
      </div>
      <div :if={@new_path}>
        <.link navigate={@new_path} class="flex items-center font-bold text-lime-500 hover:underline dark:text-lime-400">
          New <FA.icon name="plus" class="ml-2 h-4 w-4 fill-current" />
        </.link>
      </div>
      <div :if={@prev_page_path}>
        <.pagination_chevron active={@has_prev} name="chevron-left" to={@prev_page_path} />
      </div>
      <div :if={@next_page_path}>
        <.pagination_chevron active={@has_next} name="chevron-right" to={@next_page_path} />
      </div>
    </div>
    """
  end

  defp admin_menu(assigns) do
    ~H"""
    <.menu_wrapper id="admin-user-menu" user={@user}>
      <div class="py-3">
        <.link navigate={~p"/"} class="flex items-center gap-4 px-4 py-2 hover:bg-zinc-300 dark:hover:bg-zinc-700">
          <FA.icon name="arrow-right-from-bracket" class="scale-[-1] h-5 w-5 fill-current" />
          <p>Exit Admin</p>
        </.link>
        <.link
          href={~p"/users/log_out"}
          method="delete"
          class="flex items-center gap-4 px-4 py-2 hover:bg-zinc-300 dark:hover:bg-zinc-700"
        >
          <FA.icon name="arrow-right-from-bracket" class="h-5 w-5 fill-current" />
          <p>Log out</p>
        </.link>
      </div>
    </.menu_wrapper>
    """
  end

  @side_bar_open_classes "translate-x-0 ease-in opacity-100"
  @side_bar_closed_classes "-translate-x-full ease-out opacity-0"

  def close_sidebar do
    %JS{}
    |> JS.remove_class(@side_bar_open_classes, to: "#side-bar")
    |> JS.add_class(@side_bar_closed_classes, to: "#side-bar")
  end

  defp open_sidebar do
    %JS{}
    |> JS.remove_class(@side_bar_closed_classes, to: "#side-bar")
    |> JS.add_class(@side_bar_open_classes, to: "#side-bar")
  end

  attr :search_form, Form, required: true

  defp admin_table_search_form(assigns) do
    ~H"""
    <.form for={@search_form} phx-submit="search">
      <input
        id={@search_form.id}
        type="search"
        name={@search_form[:query].name}
        value={@search_form[:query].value}
        placeholder="Search"
        class="w-full border-0 border-b border-zinc-200 bg-transparent px-0 placeholder:font-bold placeholder:text-zinc-500 focus:border-0 focus:border-b focus:border-lime-500 focus:outline-none focus:ring-0 dark:border-zinc-800 dark:focus:border-lime-400"
      />
    </.form>
    """
  end

  attr :active, :boolean, required: true
  attr :name, :string, required: true
  attr :to, :string, required: true

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

  @doc """
  DEPRECATED: Use `flex_table` instead.
  """

  attr :rows, :list, required: true
  attr :row_click, :boolean, default: true
  attr :sort, :string, default: nil
  attr :actions_class, :string, default: nil

  slot :inner_block, required: true
  slot :actions
  slot :no_results

  slot :col, required: true do
    attr :label, :string
    attr :class, :string
    attr :sort_field, :string
  end

  def admin_table(assigns) do
    default_cell_class =
      if assigns.row_click, do: "p-3 text-left cursor-pointer", else: "p-3 text-left"

    default_header_class = "p-3 text-left"

    row_class =
      if assigns.row_click,
        do:
          "border-t border-zinc-200 hover:bg-zinc-200 dark:border-zinc-800 dark:hover:bg-zinc-700",
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
                <th class={[col[:class], @default_header_class]}>
                  <div
                    class={["flex items-center gap-2", if(col[:sort_field], do: "cursor-pointer select-none")]}
                    phx-click={if(col[:sort_field], do: JS.push("sort", value: %{field: col.sort_field}))}
                  >
                    <p class="truncate"><%= col[:label] %></p>
                    <.sort_icon :if={col[:sort_field]} sort={@sort} sort_field={col.sort_field} />
                  </div>
                </th>
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

  attr :rows, :list, required: true
  attr :filter, :string, default: nil
  attr :row_click, :any, default: nil

  slot :empty, required: true
  slot :row, required: true

  def flex_table(assigns) do
    ~H"""
    <%= if @rows == [] do %>
      <p class="text-lg font-semibold">
        <%= if @filter do %>
          No results for "<%= @filter %>"
        <% else %>
          <%= render_slot(@empty) %>
        <% end %>
      </p>
    <% else %>
      <.admin_table_container>
        <.admin_table_row :for={row <- @rows} phx-click={@row_click && @row_click.(row)}>
          <%= render_slot(@row, row) %>
        </.admin_table_row>
      </.admin_table_container>
    <% end %>
    """
  end

  slot :inner_block, required: true

  defp admin_table_container(assigns) do
    ~H"""
    <div class="divide-y divide-zinc-200 rounded-sm border border-zinc-200 bg-zinc-50 dark:divide-zinc-800 dark:border-zinc-800 dark:bg-zinc-900">
      <%= render_slot(@inner_block) %>
    </div>
    """
  end

  attr :rest, :global
  slot :inner_block, required: true

  defp admin_table_row(assigns) do
    ~H"""
    <div class="relative flex cursor-pointer items-center gap-4 p-4" {@rest}>
      <%= render_slot(@inner_block) %>
    </div>
    """
  end

  slot :inner_block, required: true

  def sort_button_bar(assigns) do
    ~H"""
    <div class="flex flex-wrap justify-between divide-zinc-200 rounded-sm border border-zinc-200 bg-zinc-50 font-bold dark:divide-zinc-800 dark:border-zinc-800 dark:bg-zinc-900">
      <%= render_slot(@inner_block) %>
    </div>
    """
  end

  attr :sort_field, :string, required: true
  attr :current_sort, :string, required: true
  slot :inner_block, required: true

  def sort_button(assigns) do
    ~H"""
    <div
      class="flex cursor-pointer select-none items-center gap-2 p-2"
      phx-click={JS.push("sort", value: %{field: @sort_field})}
    >
      <%= render_slot(@inner_block) %>
      <.sort_icon sort={@current_sort} sort_field={@sort_field} />
    </div>
    """
  end

  attr :sort, :string, required: true
  attr :sort_field, :string, required: true

  defp sort_icon(assigns) do
    {field, dir} = sort_field_and_dir(assigns.sort)

    assigns =
      assign(assigns,
        active: assigns.sort_field == field,
        dir: dir
      )

    ~H"""
    <FA.icon
      name={sort_icon_name(@active, @dir)}
      class={["h-4 w-4 ", if(@active, do: "fill-current", else: "fill-zinc-600")]}
    />
    """
  end

  defp sort_field_and_dir(nil), do: {nil, nil}

  defp sort_field_and_dir(sort) do
    case String.split(sort, ".") do
      [""] -> {nil, nil}
      [key] -> {key, "asc"}
      [key, dir] -> {key, dir}
      _else -> {nil, nil}
    end
  end

  defp sort_icon_name(false, _dir), do: "sort"
  defp sort_icon_name(true, "asc"), do: "sort-up"
  defp sort_icon_name(true, "desc"), do: "sort-down"
  defp sort_icon_name(_active, _dir), do: "sort"

  @doc """
  Renders a colored badge with a label in it.

  ## Examples

      <.badge color={:red}>Foo</.badge>
  """
  attr :color, :atom, doc: "one of yellow, blue, red, brand, or gray"
  attr :class, :string, default: nil
  slot :inner_block, required: true

  def badge(assigns) do
    ~H"""
    <div class={["inline-block whitespace-nowrap rounded-sm border px-1 text-zinc-900", badge_color(@color), @class]}>
      <%= render_slot(@inner_block) %>
    </div>
    """
  end

  defp badge_color(:yellow),
    do: "border-yellow-200 bg-yellow-50 dark:border-yellow-400 dark:bg-yellow-400"

  defp badge_color(:blue), do: "border-blue-200 bg-blue-50 dark:border-blue-400 dark:bg-blue-400"
  defp badge_color(:red), do: "border-red-200 bg-red-50 dark:border-red-400 dark:bg-red-400"
  defp badge_color(:brand), do: "border-lime-200 bg-lime-50 dark:border-lime-400 dark:bg-lime-400"
  defp badge_color(:gray), do: "border-zinc-200 bg-zinc-100 dark:border-zinc-400 dark:bg-zinc-400"

  attr :field, FormField, required: true

  def image_delete_button(assigns) do
    ~H"""
    <label class="flex">
      <input type="checkbox" name={@field.name} value="" class="hidden" />
      <FA.icon name="trash" class="h-4 w-4 cursor-pointer fill-current transition-colors hover:text-red-600" />
    </label>
    """
  end

  attr :field, FormField, required: true

  def delete_input(assigns) do
    ~H"""
    <input type="hidden" name={@field.name <> "[]"} />
    """
  end

  attr :field, FormField, required: true
  attr :index, :integer, required: true

  def sort_input(assigns) do
    ~H"""
    <input type="hidden" name={@field.name <> "[]"} value={@index} />
    """
  end

  attr :field, FormField, required: true
  attr :index, :integer, required: true
  attr :class, :string, default: nil, doc: "class overrides"

  def delete_button(assigns) do
    ~H"""
    <button
      type="button"
      name={@field.name <> "[]"}
      value={@index}
      phx-click={JS.dispatch("change")}
      class={["flex", @class]}
    >
      <FA.icon name="trash" class="h-4 w-4 cursor-pointer fill-current transition-colors hover:text-red-600" />
    </button>
    """
  end

  attr :field, FormField, required: true
  slot :inner_block, required: true

  def add_button(assigns) do
    ~H"""
    <button
      type="button"
      name={@field.name <> "[]"}
      value="new"
      phx-click={JS.dispatch("change")}
      class="text-brand flex cursor-pointer items-center gap-1 hover:underline dark:text-brand-dark"
    >
      <%= render_slot(@inner_block) %>
      <FA.icon name="plus" class="h-4 w-4 fill-current" />
    </button>
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

  def book_card(%{book: %AmbryScraping.GoodReads.Work{}} = assigns) do
    ~H"""
    <div class="flex gap-2 text-sm">
      <img src={@book.thumbnail} class="object-contain object-top" />
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

  def book_card(%{book: %AmbryScraping.GoodReads.Edition{}} = assigns) do
    ~H"""
    <div class="flex gap-2 text-sm">
      <img src={@book.thumbnail} class="object-contain object-top" />
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

  def book_card(%{book: %AmbryScraping.Audible.Product{}} = assigns) do
    ~H"""
    <div class="flex gap-2 text-sm">
      <img src={@book.cover_image} class="h-24 w-24" />
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

  def display_date(%PublishedDate{display_format: :full, date: date}),
    do: Calendar.strftime(date, "%B %-d, %Y")

  def display_date(%PublishedDate{display_format: :year_month, date: date}),
    do: Calendar.strftime(date, "%B %Y")

  def display_date(%PublishedDate{display_format: :year, date: date}),
    do: Calendar.strftime(date, "%Y")
end
