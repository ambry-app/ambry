defmodule AmbryWeb.CoreComponents do
  @moduledoc """
  Provides core UI components.

  The components in this module use Tailwind CSS, a utility-first CSS framework.
  See the [Tailwind CSS documentation](https://tailwindcss.com) to learn how to
  customize the generated components in this module.

  Icons are provided by [heroicons](https://heroicons.com), using the
  [heroicons_elixir](https://github.com/mveytsman/heroicons_elixir) project.
  """
  use Phoenix.Component
  use AmbryWeb, :verified_routes

  alias FontAwesome.LiveView, as: FA
  alias Phoenix.LiveView.JS

  alias Ambry.Books.Book
  alias Ambry.Series.SeriesBook

  alias AmbryWeb.Components.SearchBox

  import Phoenix.HTML, only: [raw: 1]

  import AmbryWeb.Gettext
  import AmbryWeb.Gravatar

  @doc """
  Renders a modal.

  ## Examples

      <.modal id="confirm-modal">
        Are you sure?
        <:confirm>OK</:confirm>
        <:cancel>Cancel</:cancel>
      </.modal>

  JS commands may be passed to the `:on_cancel` and `on_confirm` attributes
  for the caller to react to each button press, for example:

      <.modal id="confirm" on_confirm={JS.push("delete")} on_cancel={JS.navigate(~p"/posts")}>
        Are you sure you?
        <:confirm>OK</:confirm>
        <:cancel>Cancel</:cancel>
      </.modal>
  """
  attr :id, :string, required: true
  attr :show, :boolean, default: false
  attr :on_cancel, JS, default: %JS{}
  attr :on_confirm, JS, default: %JS{}

  slot :inner_block, required: true
  slot :title
  slot :subtitle
  slot :confirm
  slot :cancel

  def modal(assigns) do
    ~H"""
    <div id={@id} phx-mounted={@show && show_modal(@id)} phx-remove={hide_modal(@id)} class="relative z-50 hidden">
      <div id={"#{@id}-bg"} class="bg-zinc-50/90 fixed inset-0 transition-opacity" aria-hidden="true" />
      <div
        class="fixed inset-0 overflow-y-auto"
        aria-labelledby={"#{@id}-title"}
        aria-describedby={"#{@id}-description"}
        role="dialog"
        aria-modal="true"
        tabindex="0"
      >
        <div class="flex min-h-full items-center justify-center">
          <div class="w-full max-w-3xl p-4 sm:p-6 lg:py-8">
            <.focus_wrap
              id={"#{@id}-container"}
              phx-mounted={@show && show_modal(@id)}
              phx-window-keydown={hide_modal(@on_cancel, @id)}
              phx-key="escape"
              phx-click-away={hide_modal(@on_cancel, @id)}
              class="shadow-zinc-700/10 ring-zinc-700/10 relative hidden rounded-2xl bg-white p-14 shadow-lg ring-1 transition"
            >
              <div class="absolute top-6 right-5">
                <button
                  phx-click={hide_modal(@on_cancel, @id)}
                  type="button"
                  class="-m-3 flex-none p-3 opacity-20 hover:opacity-40"
                  aria-label={gettext("close")}
                >
                  <Heroicons.x_mark solid class="h-5 w-5 stroke-current" />
                </button>
              </div>
              <div id={"#{@id}-content"}>
                <header :if={@title != []}>
                  <h1 id={"#{@id}-title"} class="text-lg font-semibold leading-8 text-zinc-800">
                    <%= render_slot(@title) %>
                  </h1>
                  <p :if={@subtitle != []} id={"#{@id}-description"} class="mt-2 text-sm leading-6 text-zinc-600">
                    <%= render_slot(@subtitle) %>
                  </p>
                </header>
                <%= render_slot(@inner_block) %>
                <div :if={@confirm != [] or @cancel != []} class="mb-4 ml-6 flex items-center gap-5">
                  <.button
                    :for={confirm <- @confirm}
                    id={"#{@id}-confirm"}
                    phx-click={@on_confirm}
                    phx-disable-with
                    class="px-3 py-2"
                  >
                    <%= render_slot(confirm) %>
                  </.button>
                  <.link
                    :for={cancel <- @cancel}
                    phx-click={hide_modal(@on_cancel, @id)}
                    class="text-sm font-semibold leading-6 text-zinc-900 hover:text-zinc-700"
                  >
                    <%= render_slot(cancel) %>
                  </.link>
                </div>
              </div>
            </.focus_wrap>
          </div>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Renders flash notices.

  ## Examples

      <.flash kind={:info} flash={@flash} />
      <.flash kind={:info} phx-mounted={show("#flash")}>Welcome Back!</.flash>
  """
  attr :id, :string, default: "flash", doc: "the optional id of flash container"
  attr :flash, :map, default: %{}, doc: "the map of flash messages to display"
  attr :title, :string, default: nil
  attr :kind, :atom, values: [:info, :error], doc: "used for styling and flash lookup"
  attr :autoshow, :boolean, default: true, doc: "whether to auto show the flash on mount"
  attr :close, :boolean, default: true, doc: "whether the flash can be closed"
  attr :rest, :global, doc: "the arbitrary HTML attributes to add to the flash container"

  slot :inner_block, doc: "the optional inner block that renders the flash message"

  def flash(assigns) do
    ~H"""
    <div
      :if={msg = render_slot(@inner_block) || Phoenix.Flash.get(@flash, @kind)}
      id={@id}
      phx-mounted={@autoshow && show("##{@id}")}
      phx-click={JS.push("lv:clear-flash", value: %{key: @kind}) |> hide("##{@id}")}
      role="alert"
      class={[
        "fixed hidden top-2 right-2 w-80 sm:w-96 z-50 rounded-lg p-3 shadow-md shadow-zinc-900/5 ring-1",
        @kind == :info && "bg-emerald-50 text-emerald-800 ring-emerald-500 fill-cyan-900",
        @kind == :error && "bg-rose-50 p-3 text-rose-900 shadow-md ring-rose-500 fill-rose-900"
      ]}
      {@rest}
    >
      <p :if={@title} class="text-[0.8125rem] flex items-center gap-1.5 font-semibold leading-6">
        <Heroicons.information_circle :if={@kind == :info} mini class="h-4 w-4" />
        <Heroicons.exclamation_circle :if={@kind == :error} mini class="h-4 w-4" />
        <%= @title %>
      </p>
      <p class="text-[0.8125rem] mt-2 leading-5"><%= msg %></p>
      <button :if={@close} type="button" class="group absolute top-2 right-1 p-2" aria-label={gettext("close")}>
        <Heroicons.x_mark solid class="h-5 w-5 stroke-current opacity-40 group-hover:opacity-70" />
      </button>
    </div>
    """
  end

  @doc """
  Renders all the flash notices.

  ## Examples

      <.flashes flash={@flash} />
  """
  attr :flash, :map, default: %{}, doc: "the map of flash messages to display"

  def flashes(assigns) do
    ~H"""
    <.flash kind={:info} title="Success!" flash={@flash} />
    <.flash kind={:error} title="Error!" flash={@flash} />
    <.flash
      id="disconnected"
      kind={:error}
      title="We've lost connection to the server"
      close={false}
      autoshow={false}
      phx-disconnected={show("#disconnected")}
      phx-connected={hide("#disconnected")}
    >
      Attempting to reconnect <FA.icon name="rotate" class="ml-1 inline h-3 w-3 animate-spin" aria-hidden="true" />
    </.flash>
    """
  end

  @doc """
  Renders a simple form.

  ## Examples

      <.simple_form :let={f} for={:user} phx-change="validate" phx-submit="save">
        <.input field={{f, :email}} label="Email"/>
        <.input field={{f, :username}} label="Username" />
        <:actions>
          <.button>Save</.button>
        </:actions>
      </.simple_form>
  """
  attr :for, :any, default: nil, doc: "the datastructure for the form"
  attr :as, :any, default: nil, doc: "the server side parameter to collect all input under"

  attr :rest, :global,
    include: ~w(autocomplete name rel action enctype method novalidate target),
    doc: "the arbitrary HTML attributes to apply to the form tag"

  slot :inner_block, required: true
  slot :actions, doc: "the slot for form actions, such as a submit button"

  def simple_form(assigns) do
    ~H"""
    <.form :let={f} for={@for} as={@as} {@rest}>
      <div class="space-y-6">
        <%= render_slot(@inner_block, f) %>
        <div :for={action <- @actions} class="mt-2 flex items-center justify-between gap-6">
          <%= render_slot(action, f) %>
        </div>
      </div>
    </.form>
    """
  end

  @doc """
  Renders a button.

  ## Examples

      <.button>Send!</.button>
      <.button phx-click="go" class="ml-2">Send!</.button>
  """
  attr :type, :string, default: nil
  attr :class, :string, default: nil
  attr :rest, :global, include: ~w(disabled form name value)

  slot :inner_block, required: true

  def button(assigns) do
    ~H"""
    <button
      type={@type}
      class={[
        "phx-submit-loading:opacity-75 rounded-lg py-2 px-3",
        "text-sm font-semibold leading-6",
        "bg-zinc-900 hover:bg-zinc-700 dark:bg-brand-dark dark:hover:bg-lime-600",
        "text-white active:text-white/80 dark:text-zinc-900 dark:active:text-zinc-800",
        @class
      ]}
      {@rest}
    >
      <%= render_slot(@inner_block) %>
    </button>
    """
  end

  @doc """
  Renders an input with label and error messages.

  A `%Phoenix.HTML.Form{}` and field name may be passed to the input
  to build input names and error messages, or all the attributes and
  errors may be passed explicitly.

  ## Examples

      <.input field={{f, :email}} type="email" />
      <.input name="my-input" errors={["oh no!"]} />
  """
  attr :id, :any
  attr :name, :any
  attr :label, :string, default: nil

  attr :type, :string,
    default: "text",
    values: ~w(checkbox color date datetime-local email file hidden month number password
               range radio search select tel text textarea time url week)

  attr :value, :any
  attr :field, :any, doc: "a %Phoenix.HTML.Form{}/field name tuple, for example: {f, :email}"
  attr :errors, :list
  attr :checked, :boolean, doc: "the checked flag for checkbox inputs"
  attr :prompt, :string, default: nil, doc: "the prompt for select inputs"
  attr :options, :list, doc: "the options to pass to Phoenix.HTML.Form.options_for_select/2"
  attr :multiple, :boolean, default: false, doc: "the multiple flag for select inputs"
  attr :rest, :global, include: ~w(autocomplete cols disabled form max maxlength min minlength
                                   pattern placeholder readonly required rows size step)
  slot :inner_block

  def input(%{field: {f, field}} = assigns) do
    assigns
    |> assign(field: nil)
    |> assign_new(:name, fn ->
      name = Phoenix.HTML.Form.input_name(f, field)
      if assigns.multiple, do: name <> "[]", else: name
    end)
    |> assign_new(:id, fn -> Phoenix.HTML.Form.input_id(f, field) end)
    |> assign_new(:value, fn -> Phoenix.HTML.Form.input_value(f, field) end)
    |> assign_new(:errors, fn -> translate_errors(f.errors || [], field) end)
    |> input()
  end

  def input(%{type: "checkbox"} = assigns) do
    assigns = assign_new(assigns, :checked, fn -> input_equals?(assigns.value, "true") end)

    ~H"""
    <label phx-feedback-for={@name} class="flex items-center gap-4 text-sm leading-6 text-zinc-600 dark:text-zinc-300">
      <input type="hidden" name={@name} value="false" />
      <input
        type="checkbox"
        id={@id || @name}
        name={@name}
        value="true"
        checked={@checked}
        class={[
          "rounded",
          "bg-white border-zinc-300 text-zinc-900 focus:ring-zinc-900",
          "dark:bg-zinc-900 dark:border-zinc-700 dark:text-black dark:focus:ring-zinc-900"
        ]}
        {@rest}
      />
      <%= @label %>
    </label>
    """
  end

  def input(%{type: "select"} = assigns) do
    ~H"""
    <div phx-feedback-for={@name}>
      <.label for={@id}><%= @label %></.label>
      <select
        id={@id}
        name={@name}
        class="mt-1 block w-full rounded-md border border-zinc-300 bg-white px-3 py-2 shadow-sm focus:border-zinc-500 focus:outline-none focus:ring-zinc-500 sm:text-sm"
        multiple={@multiple}
        {@rest}
      >
        <option :if={@prompt} value=""><%= @prompt %></option>
        <%= Phoenix.HTML.Form.options_for_select(@options, @value) %>
      </select>
      <.error :for={msg <- @errors}><%= msg %></.error>
    </div>
    """
  end

  def input(%{type: "textarea"} = assigns) do
    ~H"""
    <div phx-feedback-for={@name}>
      <.label for={@id}><%= @label %></.label>
      <textarea
        id={@id || @name}
        name={@name}
        class={[
          input_border(@errors),
          "mt-2 block min-h-[6rem] w-full rounded-lg border-zinc-300 py-[7px] px-[11px]",
          "text-zinc-900 focus:border-zinc-400 focus:outline-none focus:ring-4 focus:ring-zinc-800/5 sm:text-sm sm:leading-6",
          "phx-no-feedback:border-zinc-300 phx-no-feedback:focus:border-zinc-400 phx-no-feedback:focus:ring-zinc-800/5"
        ]}
        {@rest}
      >
    <%= @value %></textarea>
      <.error :for={msg <- @errors}><%= msg %></.error>
    </div>
    """
  end

  def input(assigns) do
    ~H"""
    <div phx-feedback-for={@name}>
      <.label for={@id}><%= @label %></.label>
      <input
        type={@type}
        name={@name}
        id={@id || @name}
        value={@value}
        class={[
          input_border(@errors),
          "bg-white dark:bg-zinc-800 text-zinc-900 dark:text-zinc-300",
          "mt-2 block w-full rounded-lg py-[7px] px-[11px]",
          "focus:outline-none focus:ring-4 sm:text-sm sm:leading-6",
          "phx-no-feedback:border-zinc-300 phx-no-feedback:focus:border-zinc-400 phx-no-feedback:focus:ring-zinc-800/5",
          "dark:phx-no-feedback:border-zinc-600 dark:phx-no-feedback:focus:border-zinc-400 dark:phx-no-feedback:focus:ring-zinc-200/5"
        ]}
        {@rest}
      />
      <.error :for={msg <- @errors}><%= msg %></.error>
    </div>
    """
  end

  defp input_border([] = _errors),
    do: [
      "border-zinc-300 focus:border-zinc-400 focus:ring-zinc-800/5",
      "dark:border-zinc-600 dark:focus:border-zinc-400 dark:focus:ring-zinc-200/5"
    ]

  defp input_border([_ | _] = _errors),
    do: "border-rose-400 focus:border-rose-400 focus:ring-rose-400/10"

  @doc """
  Renders a label.
  """
  attr :for, :string, default: nil
  slot :inner_block, required: true

  def label(assigns) do
    ~H"""
    <label for={@for} class="block text-sm font-semibold leading-6 text-zinc-800 dark:text-zinc-200">
      <%= render_slot(@inner_block) %>
    </label>
    """
  end

  @doc """
  Generates a generic error message.
  """
  slot :inner_block, required: true

  def error(assigns) do
    ~H"""
    <p class="mt-3 flex gap-3 text-sm leading-6 text-red-600 phx-no-feedback:hidden">
      <Heroicons.exclamation_circle mini class="mt-0.5 h-5 w-5 flex-none fill-red-500" />
      <%= render_slot(@inner_block) %>
    </p>
    """
  end

  @doc """
  Renders a header with title.
  """
  attr :class, :string, default: nil

  slot :inner_block, required: true
  slot :subtitle
  slot :actions

  def header(assigns) do
    ~H"""
    <header class={[@actions != [] && "flex items-center justify-between gap-6", @class]}>
      <div>
        <h1 class="text-center text-xl font-extrabold leading-8 text-zinc-900 dark:text-zinc-50 sm:text-2xl">
          <%= render_slot(@inner_block) %>
        </h1>
        <p :if={@subtitle != []} class="mt-4 leading-6 text-zinc-800 dark:text-zinc-200">
          <%= render_slot(@subtitle) %>
        </p>
      </div>
      <div class="flex-none"><%= render_slot(@actions) %></div>
    </header>
    """
  end

  @doc ~S"""
  Renders a table with generic styling.

  ## Examples

      <.table id="users" rows={@users}>
        <:col :let={user} label="id"><%= user.id %></:col>
        <:col :let={user} label="username"><%= user.username %></:col>
      </.table>
  """
  attr :id, :string, required: true
  attr :row_click, :any, default: nil
  attr :rows, :list, required: true

  slot :col, required: true do
    attr :label, :string
  end

  slot :action, doc: "the slot for showing user actions in the last table column"

  def table(assigns) do
    ~H"""
    <div id={@id} class="overflow-y-auto px-4 sm:overflow-visible sm:px-0">
      <table class="w-[40rem] mt-11 sm:w-full">
        <thead class="text-[0.8125rem] text-left leading-6 text-zinc-500">
          <tr>
            <th :for={col <- @col} class="p-0 pr-6 pb-4 font-normal"><%= col[:label] %></th>
            <th class="relative p-0 pb-4"><span class="sr-only"><%= gettext("Actions") %></span></th>
          </tr>
        </thead>
        <tbody class="relative divide-y divide-zinc-100 border-t border-zinc-200 text-sm leading-6 text-zinc-700">
          <tr :for={row <- @rows} id={"#{@id}-#{Phoenix.Param.to_param(row)}"} class="group relative hover:bg-zinc-50">
            <td
              :for={{col, i} <- Enum.with_index(@col)}
              phx-click={@row_click && @row_click.(row)}
              class={["p-0", @row_click && "hover:cursor-pointer"]}
            >
              <div :if={i == 0}>
                <span class="absolute top-0 -left-4 h-full w-4 group-hover:bg-zinc-50 sm:rounded-l-xl" />
                <span class="absolute top-0 -right-4 h-full w-4 group-hover:bg-zinc-50 sm:rounded-r-xl" />
              </div>
              <div class="block py-4 pr-6">
                <span class={["relative", i == 0 && "font-semibold text-zinc-900"]}>
                  <%= render_slot(col, row) %>
                </span>
              </div>
            </td>
            <td :if={@action != []} class="w-14 p-0">
              <div class="relative whitespace-nowrap py-4 text-right text-sm font-medium">
                <span
                  :for={action <- @action}
                  class="relative ml-4 font-semibold leading-6 text-zinc-900 hover:text-zinc-700"
                >
                  <%= render_slot(action, row) %>
                </span>
              </div>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  @doc """
  Renders a data list.

  ## Examples

      <.list>
        <:item title="Title"><%= @post.title %></:item>
        <:item title="Views"><%= @post.views %></:item>
      </.list>
  """
  slot :item, required: true do
    attr :title, :string, required: true
  end

  def list(assigns) do
    ~H"""
    <div class="mt-14">
      <dl class="-my-4 divide-y divide-zinc-100">
        <div :for={item <- @item} class="flex gap-4 py-4 sm:gap-8">
          <dt class="text-[0.8125rem] w-1/4 flex-none leading-6 text-zinc-500"><%= item.title %></dt>
          <dd class="text-sm leading-6 text-zinc-700"><%= render_slot(item) %></dd>
        </div>
      </dl>
    </div>
    """
  end

  @doc """
  Renders a back navigation link.

  ## Examples

      <.back navigate={~p"/posts"}>Back to posts</.back>
  """
  attr :navigate, :any, required: true
  slot :inner_block, required: true

  def back(assigns) do
    ~H"""
    <div class="mt-16">
      <.link navigate={@navigate} class="text-sm font-semibold leading-6 text-zinc-900 hover:text-zinc-700">
        <Heroicons.arrow_left solid class="inline h-3 w-3 stroke-current" />
        <%= render_slot(@inner_block) %>
      </.link>
    </div>
    """
  end

  @doc """
  A link with brand colors and hover styling.
  """
  attr :class, :string, default: nil
  attr :rest, :global, include: ~w(navigate patch href replace method csrf_token)
  slot :inner_block, required: true

  def brand_link(assigns) do
    ~H"""
    <.link
      class={[
        "font-semibold text-brand dark:text-brand-dark hover:underline",
        @class
      ]}
      {@rest}
      phx-no-format
    ><%= render_slot(@inner_block) %></.link>
    """
  end

  @doc """
  Form card used to wrap the user auth forms.
  """
  slot :inner_block, required: true

  def auth_form_card(assigns) do
    ~H"""
    <div class="flex flex-col space-y-6 rounded-lg bg-white p-10 shadow-lg dark:bg-zinc-900">
      <%= render_slot(@inner_block) %>
    </div>
    """
  end

  @doc """
  Renders the Ambry logo with the tagline.

  ## Examples

      <.logo_with_tagline />
  """
  def logo_with_tagline(assigns) do
    ~H"""
    <div class="flex flex-col items-center">
      <div class="flex">
        <.logo class="h-12 w-12" />
        <.tagline class="h-12" />
      </div>

      <p class="font-semibold text-zinc-500 dark:text-zinc-400">
        Personal Audiobook Streaming
      </p>
    </div>
    """
  end

  @doc """
  Renders the Ambry logo SVG.

  ## Examples

      <.logo class="w-12 h-12" />
  """
  attr :class, :string, default: nil

  def logo(assigns) do
    ~H"""
    <svg
      class={["text-brand dark:text-brand-dark", @class]}
      version="1.1"
      viewBox="0 0 512 512"
      xmlns="http://www.w3.org/2000/svg"
    >
      <path
        d="m512 287.9-4e-3 112c-0.896 44.2-35.896 80.1-79.996 80.1-26.47 0-48-21.56-48-48.06v-127.84c0-26.5 21.5-48.1 48-48.1 10.83 0 20.91 2.723 30.3 6.678-12.6-103.58-100.2-182.55-206.3-182.55s-193.71 78.97-206.3 182.57c9.39-4 19.47-6.7 30.3-6.7 26.5 0 48 21.6 48 48.1v127.9c0 26.4-21.5 48-48 48-44.11 0-79.1-35.88-79.1-80.06l-0.9-111.94c0-141.2 114.8-256 256-256 140.9 0 256.5 114.56 256 255.36 0 0.2 0 0-2e-3 0.54451z"
        fill="currentColor"
      />
      <path
        d="m364 347v-138.86c0-12.782-10.366-23.143-23.143-23.143h-146.57c-25.563 0-46.286 20.723-46.286 46.286v154.29c0 25.563 20.723 46.286 46.286 46.286h154.29c8.5195 0 15.429-6.9091 15.429-14.995 0-5.6507-3.1855-10.376-7.7143-13.066v-39.227c4.725-4.6479 7.7143-10.723 7.7143-17.569zm-147.01-100.29h92.572c4.6768 0 8.1482 3.4714 8.1482 7.7143s-3.4714 7.7143-7.7143 7.7143h-93.006c-3.8089 0-7.2804-3.4714-7.2804-7.7143s3.4714-7.7143 7.2804-7.7143zm0 30.857h92.572c4.6768 0 8.1482 3.4714 8.1482 7.7143 0 4.2429-3.4714 7.7143-7.7143 7.7143h-93.006c-3.8089 0-7.2804-3.4714-7.2804-7.7143 0-4.2429 3.4714-7.7143 7.2804-7.7143zm116.15 123.43h-138.86c-8.5195 0-15.429-6.9091-15.429-15.429 0-8.5195 6.9091-15.429 15.429-15.429h138.86z"
        fill="currentColor"
      />
    </svg>
    """
  end

  @doc """
  Renders the Ambry tagline SVG.

  ## Examples

      <.tagline class="h-12" />
  """
  attr :class, :string, default: nil

  def tagline(assigns) do
    ~H"""
    <svg
      class={["text-zinc-900 dark:text-zinc-100", @class]}
      version="1.1"
      viewBox="0 0 1536 512"
      xmlns="http://www.w3.org/2000/svg"
    >
      <g fill="currentColor">
        <path d="m283.08 388.31h-123.38l-24 91.692h-95.692l140-448h82.769l140.92 448h-96.615zm-103.69-75.385h83.692l-41.846-159.69z" />
        <g>
          <path d="m533.4 146.87 62.92 240.93 62.691-240.93h87.859v333.13h-67.496v-90.147l6.1776-138.88-66.581 229.03h-45.76l-66.581-229.03 6.1775 138.88v90.147h-67.267v-333.13z" />
          <path d="m800.87 480v-333.13h102.96q52.166 0 79.165 23.338 27.227 23.109 27.227 67.953 0 25.397-11.211 43.701-11.211 18.304-30.659 26.77 22.422 6.4064 34.549 25.854 12.126 19.219 12.126 47.59 0 48.506-26.77 73.216-26.541 24.71-77.105 24.71zm67.267-144.83v89.003h43.014q18.075 0 27.456-11.211 9.3809-11.211 9.3809-31.803 0-44.845-32.49-45.989zm0-48.963h35.006q39.582 0 39.582-40.955 0-22.651-9.152-32.49t-29.744-9.8384h-35.693z" />
          <path d="m1164.7 358.28h-33.405v121.72h-67.267v-333.13h107.31q50.565 0 78.02 26.312 27.685 26.083 27.685 74.36 0 66.352-48.277 92.893l58.344 136.36v3.2032h-72.301zm-33.405-56.056h38.21q20.134 0 30.202-13.27 10.067-13.499 10.067-35.922 0-50.107-39.125-50.107h-39.354z" />
          <path d="m1412.7 296.5 50.107-149.63h73.216l-89.232 212.33v120.81h-68.182v-120.81l-89.461-212.33h73.216z" />
        </g>
      </g>
    </svg>
    """
  end

  @doc """
  A block-quote style note.
  """
  slot :inner_block, required: true

  def note(assigns) do
    ~H"""
    <p class="m-2 ml-0 border-l-4 border-zinc-400 pl-4 italic text-zinc-500 dark:border-zinc-500 dark:text-zinc-400">
      <strong>Note:</strong> <%= render_slot(@inner_block) %>
    </p>
    """
  end

  @doc """
  Renders a list of books as a responsive grid of image tiles.
  """
  def book_tiles(assigns) do
    assigns =
      assigns
      |> assign_new(:show_load_more, fn -> false end)
      |> assign_new(:load_more, fn -> {false, false} end)
      |> assign_new(:infinite_scroll_target, fn -> false end)
      |> assign_new(:current_page, fn -> 0 end)

    {load_more, target} = assigns.load_more

    ~H"""
    <.grid>
      <%= for {book, number} <- books_with_numbers(@books) do %>
        <div class="text-center">
          <%= if number do %>
            <p class="font-bold text-zinc-900 dark:text-zinc-100 sm:text-lg">Book <%= number %></p>
          <% end %>
          <div class="group">
            <.link navigate={~p"/books/#{book}"}>
              <span class="aspect-w-10 aspect-h-15 block">
                <img
                  src={book.image_path}
                  class="h-full w-full rounded-lg border border-zinc-200 object-cover object-center shadow-md dark:border-zinc-900"
                />
              </span>
            </.link>
            <p class="font-bold text-zinc-900 group-hover:underline dark:text-zinc-100 sm:text-lg">
              <.link navigate={~p"/books/#{book}"}>
                <%= book.title %>
              </.link>
            </p>
          </div>
          <p class="text-sm text-zinc-800 dark:text-zinc-200 sm:text-base">
            by <.people_links people={book.authors} />
          </p>

          <div class="text-xs text-zinc-600 dark:text-zinc-400 sm:text-sm">
            <.series_book_links series_books={book.series_books} />
          </div>
        </div>
      <% end %>

      <%= if @show_load_more do %>
        <%= if @infinite_scroll_target do %>
          <div
            id="infinite-scroll-marker"
            phx-hook="infiniteScroll"
            data-page={@current_page}
            data-target={@infinite_scroll_target}
          >
          </div>
        <% else %>
          <div class="text-center text-lg">
            <div phx-click={load_more} phx-target={target} class="group">
              <span class="aspect-w-10 aspect-h-15 block cursor-pointer">
                <span class="load-more flex h-full w-full rounded-lg border border-zinc-200 bg-zinc-200 shadow-md dark:border-zinc-700 dark:bg-zinc-700">
                  <FA.icon name="ellipsis" class="mx-auto h-12 w-12 self-center fill-current" />
                </span>
              </span>
              <p class="group-hover:underline">
                Load more
              </p>
            </div>
          </div>
        <% end %>
      <% end %>
    </.grid>
    """
  end

  defp books_with_numbers(books_assign) do
    case books_assign do
      [] -> []
      [%Book{} | _] = books -> Enum.map(books, &{&1, nil})
      [%SeriesBook{} | _] = series_books -> Enum.map(series_books, &{&1.book, &1.book_number})
    end
  end

  def player_state_tiles(assigns) do
    {load_more, target} = assigns.load_more

    ~H"""
    <.grid>
      <%= for player_state <- @player_states do %>
        <div class="text-center">
          <div class="group">
            <div class="aspect-w-10 aspect-h-15 relative">
              <img
                src={player_state.media.book.image_path}
                class="h-full w-full rounded-t-lg border border-b-0 border-zinc-200 object-cover object-center shadow-md dark:border-zinc-900"
              />
              <div class="absolute flex">
                <%!-- <div
                  id={"resume-media-#{player_state.media.id}"}
                  x-data={"{
                    id: #{player_state.media.id},
                    loaded: false
                  }"}
                  x-effect="$store.player.mediaId == id ? loaded = true : loaded = false"
                  @click={"loaded ? mediaPlayer.playPause() : mediaPlayer.loadAndPlayMedia(#{player_state.media.id})"}
                  class="mx-auto flex h-16 w-16 cursor-pointer self-center rounded-full bg-white bg-opacity-80 shadow-md backdrop-blur-sm transition group-hover:bg-opacity-100 dark:bg-black dark:bg-opacity-80"
                  phx-hook="goHome"
                >
                  <div class="mx-auto self-center fill-current pl-1" :class="{ 'pl-1': !loaded || !$store.player.playing }">
                    <span :class="{ hidden: loaded && $store.player.playing }">
                      <FA.icon name="play" class="h-7 w-7" />
                    </span>
                    <span class="hidden" :class="{ hidden: !loaded || !$store.player.playing }">
                      <FA.icon name="pause" class="h-7 w-7" />
                    </span>
                  </div>
                </div> --%>
              </div>
            </div>
            <div class="overflow-hidden rounded-b-sm border-x border-zinc-200 bg-zinc-300 shadow-sm dark:border-zinc-900 dark:bg-zinc-800">
              <div class="bg-brand h-1 dark:bg-brand-dark" style={"width: #{progress_percent(player_state)}%;"} />
            </div>
          </div>
          <p class="font-bold text-zinc-900 hover:underline dark:text-zinc-100 sm:text-lg">
            <.link navigate={~p"/books/#{player_state.media.book}"}>
              <%= player_state.media.book.title %>
            </.link>
          </p>
          <p class="text-sm text-zinc-800 dark:text-zinc-200 sm:text-base">
            by <.people_links people={player_state.media.book.authors} />
          </p>

          <p class="text-sm text-zinc-800 dark:text-zinc-200 sm:text-base">
            Narrated by <.people_links people={player_state.media.narrators} />
            <%= if player_state.media.full_cast do %>
              <span>full cast</span>
            <% end %>
          </p>

          <div class="text-xs text-zinc-600 dark:text-zinc-400 sm:text-sm">
            <.series_book_links series_books={player_state.media.book.series_books} />
          </div>
        </div>
      <% end %>

      <%= if @show_load_more do %>
        <div class="text-center text-lg">
          <div phx-click={load_more} phx-target={target} class="group">
            <span class="aspect-w-10 aspect-h-15 block cursor-pointer">
              <span class="load-more flex h-full w-full rounded-lg border border-zinc-200 bg-zinc-200 shadow-md dark:border-zinc-700 dark:bg-zinc-700">
                <FA.icon name="ellipsis" class="mx-auto h-12 w-12 self-center fill-current" />
              </span>
            </span>
            <p class="group-hover:underline">
              Load more
            </p>
          </div>
        </div>
      <% end %>
    </.grid>
    """
  end

  defp progress_percent(nil), do: "0.0"

  defp progress_percent(%{position: position, media: %{duration: duration}}) do
    position
    |> Decimal.div(duration)
    |> Decimal.mult(100)
    |> Decimal.round(1)
    |> Decimal.to_string()
  end

  @doc """
  Renders a list of links to people (like authors or narrators) separated by commas.
  """
  def people_links(assigns) do
    assigns =
      assign_new(assigns, :classes, fn ->
        underline_class =
          if Map.get(assigns, :underline, true) do
            "hover:underline"
          end

        link_class = assigns[:link_class]

        [underline_class, link_class] |> Enum.join(" ") |> String.trim()
      end)

    ~H"""
    <%= for person_ish <- @people do %>
      <.link navigate={~p"/people/#{person_ish.person_id}"} class={@classes} phx-no-format>
        <%= person_ish.name %>
      </.link><span
        class="last:hidden"
        phx-no-format
      >,</span>
    <% end %>
    """
  end

  @doc """
  Renders a list of links to series, each in its own p tag.
  """
  def series_book_links(assigns) do
    ~H"""
    <%= for series_book <- Enum.sort_by(@series_books, & &1.series.name) do %>
      <p>
        <.link navigate={~p"/series/#{series_book.series}"} class="hover:underline">
          <%= series_book.series.name %> #<%= series_book.book_number %>
        </.link>
      </p>
    <% end %>
    """
  end

  @doc """
  A section header
  """
  slot :inner_block, required: true

  def section_header(assigns) do
    ~H"""
    <h1 class="mb-6 text-3xl font-bold text-zinc-100 md:mb-8 md:text-4xl lg:mb-12 lg:text-5xl">
      <%= render_slot(@inner_block) %>
    </h1>
    """
  end

  @doc """
  A flexible grid of things
  """
  slot :inner_block, required: true

  def grid(assigns) do
    ~H"""
    <div class="grid grid-cols-2 gap-4 sm:grid-cols-3 sm:gap-6 md:grid-cols-4 md:gap-8 lg:grid-cols-5 xl:grid-cols-6 2xl:grid-cols-7">
      <%= render_slot(@inner_block) %>
    </div>
    """
  end

  @doc """
  Main app navigation header
  """
  def nav_header(assigns) do
    ~H"""
    <header id="nav-header" class="border-zinc-100 dark:border-zinc-900">
      <div class="flex p-4 text-zinc-600 dark:text-zinc-500">
        <div class="flex-1">
          <.link navigate={~p"/"} class="flex">
            <.ambry_icon class="mt-1 h-6 w-6 lg:h-7 lg:w-7" />
            <.ambry_title class="mt-1 hidden h-6 md:block lg:h-7" />
          </.link>
        </div>
        <div class="flex-1">
          <div class="flex justify-center gap-8 lg:gap-12">
            <.link navigate={~p"/"} class={nav_class(@active_path == "/")}>
              <span title="Now playing"><FA.icon name="circle-play" class="mt-1 h-6 w-6 fill-current lg:hidden" /></span>
              <span class="hidden text-xl font-bold lg:block">Now Playing</span>
            </.link>
            <.link navigate={~p"/library"} class={nav_class(@active_path == "/library")}>
              <span title="Library"><FA.icon name="book-open" class="mt-1 h-6 w-6 fill-current lg:hidden" /></span>
              <span class="hidden text-xl font-bold lg:block">Library</span>
            </.link>
            <span
              phx-click={show_search()}
              class={nav_class(String.starts_with?(@active_path, "/search"), "flex content-center gap-4 cursor-pointer")}
            >
              <span title="Search">
                <FA.icon name="magnifying-glass" class="mt-1 h-6 w-6 fill-current lg:h-5 lg:w-5" />
              </span>
              <span class="hidden text-xl font-bold xl:block">Search</span>
            </span>
          </div>
        </div>
        <div class="flex-1">
          <div class="flex">
            <div class="grow" />
            <div phx-click-away={hide_menu("user-menu")} phx-window-keydown={hide_menu("user-menu")} phx-key="escape">
              <img
                phx-click={toggle_menu("user-menu")}
                class="mt-1 h-6 cursor-pointer rounded-full lg:h-7 lg:w-7"
                src={gravatar_url(@user.email)}
              />
              <.user_menu user={@user} />
            </div>
          </div>
        </div>
      </div>

      <.live_component module={SearchBox} id="search-box" path={@active_path} />
    </header>
    """
  end

  def ambry_icon(assigns) do
    extra_classes = assigns[:class] || ""
    default_classes = "text-brand dark:text-brand-dark"
    assigns = assign(assigns, :class, String.trim("#{default_classes} #{extra_classes}"))

    ~H"""
    <svg class={@class} version="1.1" viewBox="0 0 512 512" xmlns="http://www.w3.org/2000/svg">
      <path
        d="m512 287.9-4e-3 112c-0.896 44.2-35.896 80.1-79.996 80.1-26.47 0-48-21.56-48-48.06v-127.84c0-26.5 21.5-48.1 48-48.1 10.83 0 20.91 2.723 30.3 6.678-12.6-103.58-100.2-182.55-206.3-182.55s-193.71 78.97-206.3 182.57c9.39-4 19.47-6.7 30.3-6.7 26.5 0 48 21.6 48 48.1v127.9c0 26.4-21.5 48-48 48-44.11 0-79.1-35.88-79.1-80.06l-0.9-111.94c0-141.2 114.8-256 256-256 140.9 0 256.5 114.56 256 255.36 0 0.2 0 0-2e-3 0.54451z"
        fill="currentColor"
      />
      <path
        d="m364 347v-138.86c0-12.782-10.366-23.143-23.143-23.143h-146.57c-25.563 0-46.286 20.723-46.286 46.286v154.29c0 25.563 20.723 46.286 46.286 46.286h154.29c8.5195 0 15.429-6.9091 15.429-14.995 0-5.6507-3.1855-10.376-7.7143-13.066v-39.227c4.725-4.6479 7.7143-10.723 7.7143-17.569zm-147.01-100.29h92.572c4.6768 0 8.1482 3.4714 8.1482 7.7143s-3.4714 7.7143-7.7143 7.7143h-93.006c-3.8089 0-7.2804-3.4714-7.2804-7.7143s3.4714-7.7143 7.2804-7.7143zm0 30.857h92.572c4.6768 0 8.1482 3.4714 8.1482 7.7143 0 4.2429-3.4714 7.7143-7.7143 7.7143h-93.006c-3.8089 0-7.2804-3.4714-7.2804-7.7143 0-4.2429 3.4714-7.7143 7.2804-7.7143zm116.15 123.43h-138.86c-8.5195 0-15.429-6.9091-15.429-15.429 0-8.5195 6.9091-15.429 15.429-15.429h138.86z"
        fill="currentColor"
      />
    </svg>
    """
  end

  def ambry_title(assigns) do
    extra_classes = assigns[:class] || ""
    default_classes = "text-zinc-900 dark:text-zinc-100"
    assigns = assign(assigns, :class, String.trim("#{default_classes} #{extra_classes}"))

    ~H"""
    <svg class={@class} version="1.1" viewBox="0 0 1536 512" xmlns="http://www.w3.org/2000/svg">
      <g fill="currentColor">
        <path d="m283.08 388.31h-123.38l-24 91.692h-95.692l140-448h82.769l140.92 448h-96.615zm-103.69-75.385h83.692l-41.846-159.69z" />
        <g>
          <path d="m533.4 146.87 62.92 240.93 62.691-240.93h87.859v333.13h-67.496v-90.147l6.1776-138.88-66.581 229.03h-45.76l-66.581-229.03 6.1775 138.88v90.147h-67.267v-333.13z" />
          <path d="m800.87 480v-333.13h102.96q52.166 0 79.165 23.338 27.227 23.109 27.227 67.953 0 25.397-11.211 43.701-11.211 18.304-30.659 26.77 22.422 6.4064 34.549 25.854 12.126 19.219 12.126 47.59 0 48.506-26.77 73.216-26.541 24.71-77.105 24.71zm67.267-144.83v89.003h43.014q18.075 0 27.456-11.211 9.3809-11.211 9.3809-31.803 0-44.845-32.49-45.989zm0-48.963h35.006q39.582 0 39.582-40.955 0-22.651-9.152-32.49t-29.744-9.8384h-35.693z" />
          <path d="m1164.7 358.28h-33.405v121.72h-67.267v-333.13h107.31q50.565 0 78.02 26.312 27.685 26.083 27.685 74.36 0 66.352-48.277 92.893l58.344 136.36v3.2032h-72.301zm-33.405-56.056h38.21q20.134 0 30.202-13.27 10.067-13.499 10.067-35.922 0-50.107-39.125-50.107h-39.354z" />
          <path d="m1412.7 296.5 50.107-149.63h73.216l-89.232 212.33v120.81h-68.182v-120.81l-89.461-212.33h73.216z" />
        </g>
      </g>
    </svg>
    """
  end

  defp nav_class(active?, extra \\ "")
  defp nav_class(true, extra), do: "text-zinc-900 dark:text-zinc-100 #{extra}"
  defp nav_class(false, extra), do: "hover:text-zinc-900 dark:hover:text-zinc-100 #{extra}"

  def user_menu(assigns) do
    ~H"""
    <.menu_wrapper id="user-menu" user={@user}>
      <div class="py-3">
        <%= if @user.admin do %>
          <.link navigate={~p"/admin"} class="flex items-center gap-4 px-4 py-2 hover:bg-zinc-300 dark:hover:bg-zinc-700">
            <FA.icon name="screwdriver-wrench" class="h-5 w-5 fill-current" />
            <p>Admin</p>
          </.link>
        <% end %>
        <.link
          navigate={~p"/users/settings"}
          class="flex items-center gap-4 px-4 py-2 hover:bg-zinc-300 dark:hover:bg-zinc-700"
        >
          <FA.icon name="user-gear" class="h-5 w-5 fill-current" />
          <p>Account Settings</p>
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

  defp menu_wrapper(assigns) do
    ~H"""
    <div id={@id} class="max-w-80 absolute top-12 right-4 z-50 hidden text-zinc-800 shadow-md dark:text-zinc-200">
      <div class="h-full w-full divide-y divide-zinc-200 rounded-sm border border-zinc-200 bg-zinc-50 dark:divide-zinc-800 dark:border-zinc-800 dark:bg-zinc-900">
        <div class="flex items-center gap-4 p-4">
          <img class="h-10 w-10 rounded-full" src={gravatar_url(@user.email)} />
          <p class="overflow-hidden text-ellipsis whitespace-nowrap"><%= @user.email %></p>
        </div>
        <%= render_slot(@inner_block) %>
      </div>
    </div>
    """
  end

  attr :content, :string, required: true
  attr :class, :string, default: nil

  def markdown(assigns) do
    ~H"""
    <article class={["prose prose-zinc dark:prose-invert", @class]}>
      <%= raw(Earmark.as_html!(@content)) %>
    </article>
    """
  end

  ## JS Commands

  def show(js \\ %JS{}, selector) do
    JS.show(js,
      to: selector,
      transition: transition_in()
    )
  end

  def hide(js \\ %JS{}, selector) do
    JS.hide(js,
      to: selector,
      time: 200,
      transition: transition_out()
    )
  end

  def show_modal(js \\ %JS{}, id) when is_binary(id) do
    js
    |> JS.show(to: "##{id}")
    |> JS.show(
      to: "##{id}-bg",
      transition: {"transition-all transform ease-out duration-300", "opacity-0", "opacity-100"}
    )
    |> show("##{id}-container")
    |> JS.add_class("overflow-hidden", to: "body")
    |> JS.focus_first(to: "##{id}-content")
  end

  def hide_modal(js \\ %JS{}, id) do
    js
    |> JS.hide(
      to: "##{id}-bg",
      transition: {"transition-all transform ease-in duration-200", "opacity-100", "opacity-0"}
    )
    |> hide("##{id}-container")
    |> JS.hide(to: "##{id}", transition: {"block", "block", "hidden"})
    |> JS.remove_class("overflow-hidden", to: "body")
    |> JS.pop_focus()
  end

  defp toggle_menu(js \\ %JS{}, id) do
    JS.toggle(js,
      to: "##{id}",
      time: 100,
      in: transition_in(),
      out: transition_out()
    )
  end

  defp hide_menu(js \\ %JS{}, id) do
    JS.hide(js,
      to: "##{id}",
      time: 100,
      transition: transition_out()
    )
  end

  def show_search(js \\ %JS{}) do
    js
    |> JS.show(
      to: "#search-box",
      time: 100,
      transition: transition_in()
    )
    |> JS.focus(to: "#search-input")
    |> JS.dispatch("ambry:search-box-shown", to: "#search-box")
  end

  def hide_search(js \\ %JS{}) do
    js
    |> JS.hide(
      to: "#search-box",
      time: 100,
      transition: transition_out()
    )
    |> JS.dispatch("ambry:search-box-hidden", to: "#search-box")
  end

  defp transition_in do
    {"transition-all transform ease-out duration-300",
     "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95",
     "opacity-100 translate-y-0 sm:scale-100"}
  end

  defp transition_out do
    {"transition-all transform ease-in duration-200", "opacity-100 translate-y-0 sm:scale-100",
     "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95"}
  end

  @doc """
  Translates an error message using gettext.
  """
  def translate_error({msg, opts}) do
    # When using gettext, we typically pass the strings we want
    # to translate as a static argument:
    #
    #     # Translate "is invalid" in the "errors" domain
    #     dgettext("errors", "is invalid")
    #
    #     # Translate the number of files with plural rules
    #     dngettext("errors", "1 file", "%{count} files", count)
    #
    # Because the error messages we show in our forms and APIs
    # are defined inside Ecto, we need to translate them dynamically.
    # This requires us to call the Gettext module passing our gettext
    # backend as first argument.
    #
    # Note we use the "errors" domain, which means translations
    # should be written to the errors.po file. The :count option is
    # set by Ecto and indicates we should also apply plural rules.
    if count = opts[:count] do
      Gettext.dngettext(AmbryWeb.Gettext, "errors", msg, msg, count, opts)
    else
      Gettext.dgettext(AmbryWeb.Gettext, "errors", msg, opts)
    end
  end

  @doc """
  Translates the errors for a field from a keyword list of errors.
  """
  def translate_errors(errors, field) when is_list(errors) do
    for {^field, {msg, opts}} <- errors, do: translate_error({msg, opts})
  end

  defp input_equals?(val1, val2) do
    Phoenix.HTML.html_escape(val1) == Phoenix.HTML.html_escape(val2)
  end
end
