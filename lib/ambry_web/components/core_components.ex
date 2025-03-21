defmodule AmbryWeb.CoreComponents do
  @moduledoc """
  Provides core UI components.

  The components in this module use Tailwind CSS, a utility-first CSS framework.
  See the [Tailwind CSS documentation](https://tailwindcss.com) to learn how to
  customize the generated components in this module.
  """
  use Phoenix.Component
  use AmbryWeb, :verified_routes
  use Gettext, backend: AmbryWeb.Gettext

  import AmbryWeb.Gravatar
  import Phoenix.HTML, only: [raw: 1]

  alias Ambry.Books.Book
  alias Ambry.Books.SeriesBook
  alias Ambry.Media.Media
  alias Ambry.Media.PlayerState
  alias AmbryWeb.Admin.UploadHelpers
  alias AmbryWeb.Components.Autocomplete
  alias AmbryWeb.Player
  alias FontAwesome.LiveView, as: FA
  alias Phoenix.HTML.Form
  alias Phoenix.HTML.FormField
  alias Phoenix.LiveView.JS

  @doc """
  Renders a modal.

  ## Examples

      <.modal id="confirm-modal">
        This is a modal.
      </.modal>

  JS commands may be passed to the `:on_cancel` to configure
  the closing/cancel event, for example:

      <.modal id="confirm" on_cancel={JS.navigate(~p"/posts")}>
        This is another modal.
      </.modal>
  """
  attr :id, :string, required: true
  attr :show, :boolean, default: false
  attr :on_cancel, JS, default: %JS{}

  slot :inner_block, required: true

  def modal(assigns) do
    ~H"""
    <div
      id={@id}
      phx-mounted={@show && show_modal(@id)}
      phx-remove={hide_modal(@id)}
      data-cancel={JS.exec(@on_cancel, "phx-remove")}
      class="relative z-40 hidden"
    >
      <div
        id={"#{@id}-bg"}
        class="border-brand bg-white/90 fixed inset-0 border-l-4 backdrop-blur transition-opacity dark:border-brand-dark dark:bg-black/90"
        aria-hidden="true"
      />
      <div
        class="fixed inset-0 overflow-y-auto"
        aria-labelledby={"#{@id}-title"}
        aria-describedby={"#{@id}-description"}
        role="dialog"
        aria-modal="true"
        tabindex="0"
      >
        <.focus_wrap
          id={"#{@id}-container"}
          phx-window-keydown={JS.exec("data-cancel", to: "##{@id}")}
          phx-key="escape"
          class="relative transition"
        >
          <div class="absolute top-6 right-5">
            <button
              phx-click={JS.exec("data-cancel", to: "##{@id}")}
              type="button"
              class="-m-3 flex-none p-3 opacity-20 hover:opacity-40"
              aria-label={gettext("close")}
            >
              <FA.icon name="xmark" class="h-5 w-5 fill-current" />
            </button>
          </div>
          <div id={"#{@id}-content"}>
            {render_slot(@inner_block)}
          </div>
        </.focus_wrap>
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
  attr :id, :string, doc: "the optional id of flash container"
  attr :flash, :map, default: %{}, doc: "the map of flash messages to display"
  attr :title, :string, default: nil
  attr :kind, :atom, values: [:info, :error], doc: "used for styling and flash lookup"
  attr :rest, :global, doc: "the arbitrary HTML attributes to add to the flash container"

  slot :inner_block, doc: "the optional inner block that renders the flash message"

  def flash(assigns) do
    assigns = assign_new(assigns, :id, fn -> "flash-#{assigns.kind}" end)

    ~H"""
    <div
      :if={msg = render_slot(@inner_block) || Phoenix.Flash.get(@flash, @kind)}
      id={@id}
      phx-click={JS.push("lv:clear-flash", value: %{key: @kind}) |> hide("##{@id}")}
      role="alert"
      class={[
        "fixed top-2 right-2 z-50 w-80 rounded-sm p-3 shadow-md ring-1 sm:w-96",
        "shadow-zinc-900/5 fill-zinc-900 text-zinc-900",
        @kind == :info && "bg-lime-50 ring-lime-200 dark:bg-lime-400 dark:ring-lime-400",
        @kind == :error && "bg-red-50 ring-red-200 dark:bg-red-400 dark:ring-red-400"
      ]}
      {@rest}
    >
      <p :if={@title} class="flex items-center gap-1.5 text-sm font-semibold leading-6">
        <FA.icon :if={@kind == :info} name="circle-info" class="h-4 w-4" />
        <FA.icon :if={@kind == :error} name="circle-exclamation" class="h-4 w-4" />
        {@title}
      </p>
      <p class="mt-2 text-sm leading-5">{msg}</p>
      <button type="button" class="group absolute top-1 right-1 p-2" aria-label={gettext("close")}>
        <FA.icon name="xmark" class="h-5 w-5 opacity-20 hover:opacity-40" />
      </button>
    </div>
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id}>
      <.flash kind={:info} title={gettext("Success!")} flash={@flash} />
      <.flash kind={:error} title={gettext("Error!")} flash={@flash} />
      <.flash
        id="client-error"
        kind={:error}
        title="We've lost connection to the server"
        phx-disconnected={show(".phx-client-error #client-error")}
        phx-connected={hide("#client-error")}
        hidden
      >
        Attempting to reconnect <FA.icon name="rotate" class="ml-1 inline h-3 w-3 animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title="Something went wrong!"
        phx-disconnected={show(".phx-server-error #server-error")}
        phx-connected={hide("#server-error")}
        hidden
      >
        Hang in there while we get back on track <FA.icon name="rotate" class="ml-1 inline h-3 w-3 animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Renders a simple form.

  ## Examples

      <.simple_form for={@form} phx-change="validate" phx-submit="save">
        <.input field={@form[:email]} label="Email"/>
        <.input field={@form[:username]} label="Username" />
        <:actions>
          <.button>Save</.button>
        </:actions>
      </.simple_form>
  """
  attr :for, :any, required: true, doc: "the data structure for the form"
  attr :as, :any, default: nil, doc: "the server side parameter to collect all input under"

  attr :rest, :global,
    include: ~w(autocomplete name rel action enctype method novalidate target),
    doc: "the arbitrary HTML attributes to apply to the form tag"

  attr :container_class, :string, default: nil, doc: "extra classes for the container div"

  slot :inner_block, required: true
  slot :actions, doc: "the slot for form actions, such as a submit button"

  def simple_form(assigns) do
    ~H"""
    <.form :let={f} for={@for} as={@as} {@rest}>
      <div class={["space-y-6", @container_class]}>
        {render_slot(@inner_block, f)}
        <div :for={action <- @actions} class="mt-2 flex items-center justify-between gap-6">
          {render_slot(action, f)}
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
  attr :color, :atom, default: :brand, values: ~w(brand yellow red zinc)a
  attr :rest, :global, include: ~w(disabled form name value)

  slot :inner_block, required: true

  def button(assigns) do
    ~H"""
    <button
      type={@type}
      class={[
        "rounded-sm px-3 py-2 phx-submit-loading:opacity-75",
        "text-sm font-semibold leading-6",
        "text-white active:text-white/80 dark:text-zinc-900 dark:active:text-zinc-800",
        button_color_classes(@color),
        @class
      ]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </button>
    """
  end

  defp button_color_classes(:brand) do
    "bg-zinc-900 hover:bg-zinc-700 dark:bg-brand-dark dark:hover:bg-lime-600"
  end

  defp button_color_classes(:yellow) do
    "bg-yellow-500 hover:bg-yellow-700 dark:bg-yellow-400 dark:hover:bg-yellow-600"
  end

  defp button_color_classes(:red) do
    "bg-red-500 hover:bg-red-700 dark:bg-red-400 dark:hover:bg-red-600"
  end

  defp button_color_classes(:zinc) do
    "bg-zinc-600 hover:bg-zinc-800 dark:bg-zinc-400 dark:hover:bg-zinc-600"
  end

  @doc """
  Renders an input with label and error messages.

  A `%Phoenix.HTML.Form{}` and field name may be passed to the input
  to build input names and error messages, or all the attributes and
  errors may be passed explicitly.

  ## Examples

      <.input field={@form[:email]} type="email" />
      <.input name="my-input" errors={["oh no!"]} />
  """
  attr :id, :any, default: nil
  attr :name, :any
  attr :label, :string, default: nil
  attr :value, :any

  attr :type, :string,
    default: "text",
    values: ~w(checkbox color date datetime-local email file hidden month number password
               range radio search select tel text textarea time url week autocomplete)

  attr :field, FormField,
    doc: "a form field struct retrieved from the form, for example: @form[:email]"

  attr :errors, :list, default: []
  attr :show_errors, :boolean, default: true, doc: "disables the rendering of errors if false"
  attr :checked, :boolean, doc: "the checked flag for checkbox inputs"
  attr :prompt, :string, default: nil, doc: "the prompt for select inputs"
  attr :options, :list, doc: "the options to pass to Phoenix.HTML.Form.options_for_select/2"
  attr :multiple, :boolean, default: false, doc: "the multiple flag for select inputs"
  attr :class, :string, default: nil, doc: "class overrides"
  attr :container_class, :string, default: nil, doc: "extra classes for the container div"

  attr :rest, :global,
    include: ~w(autocomplete cols disabled form list max maxlength min minlength
                pattern placeholder readonly required rows size step)

  def input(%{field: %FormField{} = field} = assigns) do
    errors = if Phoenix.Component.used_input?(field), do: field.errors, else: []

    assigns
    |> assign(field: nil, id: assigns.id || field.id)
    |> assign(:errors, Enum.map(errors, &translate_error(&1)))
    |> assign_new(:name, fn -> if assigns.multiple, do: field.name <> "[]", else: field.name end)
    |> assign_new(:value, fn -> field.value end)
    |> input()
  end

  def input(%{type: "checkbox"} = assigns) do
    assigns =
      assign_new(assigns, :checked, fn ->
        Form.normalize_value("checkbox", assigns[:value])
      end)

    ~H"""
    <div class={[@container_class]}>
      <.label class="flex items-center gap-4">
        <input type="hidden" name={@name} value="false" disabled={@rest[:disabled]} />
        <input
          type="checkbox"
          id={@id}
          name={@name}
          value="true"
          checked={@checked}
          class={[
            "rounded",
            "border-zinc-300 bg-white text-zinc-900 focus:ring-zinc-900",
            "dark:border-none dark:bg-zinc-800 dark:text-zinc-800 dark:focus:ring-zinc-900",
            @class
          ]}
          {@rest}
        />
        {@label}
      </.label>
      <.error :for={msg <- @errors} :if={@show_errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "select"} = assigns) do
    ~H"""
    <div class={["space-y-2", @container_class]}>
      <.label :if={@label} for={@id}>{@label}</.label>
      <select
        id={@id}
        name={@name}
        class={
          ["py-[7px] px-[11px] block w-full rounded-sm", "focus:outline-none focus:ring-4 sm:text-sm sm:leading-6"] ++
            input_color_classes(@errors) ++ [@class]
        }
        multiple={@multiple}
        {@rest}
      >
        <option :if={@prompt} value="">{@prompt}</option>
        {Form.options_for_select(@options, @value)}
      </select>
      <.error :for={msg <- @errors} :if={@show_errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "textarea"} = assigns) do
    ~H"""
    <div class={["space-y-2", @container_class]}>
      <.label :if={@label} for={@id}>{@label}</.label>
      <textarea
        id={@id}
        name={@name}
        class={
          ["min-h-48 py-[7px] px-[11px] block w-full rounded-sm", "focus:outline-none focus:ring-4 sm:text-sm sm:leading-6"] ++
            input_color_classes(@errors) ++ [@class]
        }
        {@rest}
      ><%= Form.normalize_value("textarea", @value) %></textarea>
      <.error :for={msg <- @errors} :if={@show_errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "autocomplete"} = assigns) do
    ~H"""
    <div class={["space-y-2", @container_class]}>
      <.label :if={@label} for={@id}>{@label}</.label>
      <.live_component
        module={Autocomplete}
        id={@id}
        name={@name}
        options={@options}
        value={@value}
        class={
          ["py-[7px] px-[11px] block w-full rounded-sm", "focus:outline-none focus:ring-4 sm:text-sm sm:leading-6"] ++
            input_color_classes(@errors) ++ [@class]
        }
        {@rest}
      />
      <.error :for={msg <- @errors} :if={@show_errors}>{msg}</.error>
    </div>
    """
  end

  # All other inputs text, datetime-local, url, password, etc. are handled here...
  def input(assigns) do
    ~H"""
    <div class={["space-y-2", @container_class]}>
      <.label :if={@label} for={@id}>{@label}</.label>
      <input
        type={@type}
        name={@name}
        id={@id}
        value={Form.normalize_value(@type, @value)}
        class={
          ["py-[7px] px-[11px] block w-full rounded-sm", "focus:outline-none focus:ring-4 sm:text-sm sm:leading-6"] ++
            input_color_classes(@errors) ++ [@class]
        }
        {@rest}
      />
      <.error :for={msg <- @errors} :if={@show_errors}>{msg}</.error>
    </div>
    """
  end

  @doc """
  For if you want to have more control over where form field errors are rendered.
  """
  attr :field, FormField,
    doc: "a form field struct retrieved from the form, for example: @form[:email]"

  attr :multiple, :boolean, default: false, doc: "the multiple flag for select inputs"

  def field_errors(%{field: %FormField{} = field} = assigns) do
    assigns =
      assigns
      |> assign(field: nil)
      |> assign(:errors, Enum.map(field.errors, &translate_error(&1)))
      |> assign_new(:name, fn -> if assigns.multiple, do: field.name <> "[]", else: field.name end)

    ~H"""
    <div>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  attr :upload, :any, required: true
  attr :on_cancel, :string, required: true
  attr :label, :string, default: nil
  attr :class, :string, default: nil, doc: "class overrides"
  attr :errors, :list, default: []
  attr :image_preview_class, :string, default: nil

  def file_input(assigns) do
    ~H"""
    <div>
      <div class="space-y-2">
        <.label :if={@label}>{@label}</.label>
        <.live_file_input
          upload={@upload}
          class={
            [
              "!text-zinc-500 block w-full rounded-sm rounded-b-none border p-0",
              "focus:outline-none focus:ring-4 sm:text-sm sm:leading-6",
              "file:p-[11px] file:cursor-pointer file:rounded-none file:border-0",
              "file:bg-zinc-600 file:font-bold file:text-zinc-100 hover:file:bg-zinc-500"
            ] ++ input_color_classes(@errors) ++ [@class]
          }
        />
      </div>
      <div
        class="space-y-4 rounded-b-sm border-2 border-t-0 border-dashed border-zinc-600 bg-zinc-950 p-4"
        phx-drop-target={@upload.ref}
      >
        <FA.icon :if={@upload.entries == []} name="upload" class="mx-auto my-4 block h-8 w-8 fill-current" />
        <div :if={@upload.entries != []} class="flex flex-wrap gap-4">
          <article :for={entry <- @upload.entries} class="inline-block">
            <figure>
              <.live_image_preview_with_size
                :if={UploadHelpers.image?(entry.client_type)}
                entry={entry}
                class={@image_preview_class}
              />
              <figcaption>{entry.client_name}</figcaption>
            </figure>

            <progress value={entry.progress} max="100">{entry.progress}%</progress>

            <span
              class="cursor-pointer text-2xl transition-colors hover:text-red-600 dark:hover:text-red-500"
              phx-click={JS.push(@on_cancel, value: %{ref: entry.ref})}
            >
              &times;
            </span>

            <p :for={err <- upload_errors(@upload, entry)} class="text-red-600 dark:text-red-500">
              {UploadHelpers.upload_error_to_string(err)}
            </p>
          </article>
        </div>
        <p :for={err <- upload_errors(@upload)} class="text-red-600 dark:text-red-500">
          {UploadHelpers.upload_error_to_string(err)}
        </p>
      </div>
    </div>
    """
  end

  attr :label, :string, default: nil
  attr :field, FormField, required: true
  attr :image_preview_class, :string, default: nil

  def image_import_input(assigns) do
    assigns = assign(assigns, :show_preview, UploadHelpers.valid_image_url?(assigns.field.value))

    ~H"""
    <div>
      <.input
        field={@field}
        label={@label}
        placeholder="https://some-image.com/url"
        class={if @show_preview, do: "rounded-b-none"}
      />
      <div :if={@show_preview} class="rounded-b-sm border-2 border-t-0 border-dashed border-zinc-600 bg-zinc-950 p-4">
        <.image_with_size id={@field.id} src={@field.value} class={@image_preview_class} />
      </div>
    </div>
    """
  end

  defp input_color_classes(errors) do
    [
      "bg-white text-zinc-900 placeholder:text-zinc-500",
      "dark:bg-zinc-800 dark:text-zinc-300",
      "border-zinc-300 focus:border-zinc-400 focus:ring-zinc-800/5",
      "dark:border-zinc-600 dark:focus:border-zinc-400 dark:focus:ring-zinc-200/5",
      "phx-no-feedback:border-zinc-300 phx-no-feedback:focus:border-zinc-400 phx-no-feedback:focus:ring-zinc-800/5",
      "phx-no-feedback:dark:border-zinc-600 phx-no-feedback:dark:focus:border-zinc-400 phx-no-feedback:dark:focus:ring-zinc-200/5"
    ] ++
      if errors == [],
        do: [],
        else: [
          "border-rose-400 focus:border-rose-400 focus:ring-rose-400/10",
          "dark:border-red-400 dark:focus:border-red-400 dark:focus:ring-red-400/10"
        ]
  end

  @doc """
  Renders a tab bar style radio-group when given a form field.
  """
  attr :label, :string, default: nil
  attr :field, FormField, required: true
  attr :options, :list, required: true

  slot :inner_block, required: true

  def tabs(assigns) do
    ~H"""
    <div class="flex items-center gap-2">
      {render_slot(@inner_block)}

      <span class="cursor-default select-none text-sm">•</span>

      <.intersperse :let={{label, value}} enum={@options}>
        <:separator>
          <span class="cursor-default select-none text-sm">•</span>
        </:separator>
        <label class="cursor-pointer select-none whitespace-nowrap text-sm italic leading-6 has-[:checked]:font-semibold has-[:checked]:not-italic has-[:checked]:underline">
          <input type="radio" name={@field.name} value={value} checked={@field.value == value} class="hidden" /> {label}
        </label>
      </.intersperse>
    </div>
    """
  end

  @doc """
  Renders a label.
  """
  attr :for, :string, default: nil
  attr :class, :string, default: nil, doc: "class overrides"
  slot :inner_block, required: true

  def label(assigns) do
    ~H"""
    <label
      for={@for}
      class={["block whitespace-nowrap text-sm font-semibold leading-6 text-zinc-800 dark:text-zinc-200", @class]}
    >
      {render_slot(@inner_block)}
    </label>
    """
  end

  @doc """
  Generates a generic error message.
  """
  slot :inner_block, required: true

  def error(assigns) do
    ~H"""
    <p class="flex items-center gap-3 text-sm leading-6 text-red-600 phx-no-feedback:hidden dark:text-red-500">
      <FA.icon name="circle-exclamation" class="h-4 w-4 flex-none fill-red-500" />
      {render_slot(@inner_block)}
    </p>
    """
  end

  slot :inner_block, required: true

  def loading(assigns) do
    ~H"""
    <p class="flex items-center gap-3 text-sm font-semibold leading-6">
      <FA.icon name="rotate" class="h-4 w-4 flex-none animate-spin fill-zinc-800 dark:fill-zinc-200" />
      {render_slot(@inner_block)}
    </p>
    """
  end

  attr :id, :string, required: true
  attr :src, :string, required: true
  attr :class, :string, default: nil

  def image_with_size(assigns) do
    ~H"""
    <div>
      <div class="inline-block">
        <img id={"#{@id}-preview"} src={@src} class={@class} />
        <p
          id={"#{@id}-size"}
          class="text-center text-xs text-zinc-700"
          phx-hook="image-size"
          data-target={"#{@id}-preview"}
          phx-update="ignore"
        />
      </div>
    </div>
    """
  end

  attr :entry, Phoenix.LiveView.UploadEntry, required: true
  attr :class, :string, default: nil

  def live_image_preview_with_size(assigns) do
    ~H"""
    <div>
      <div class="inline-block">
        <.live_img_preview entry={@entry} class={@class} />
        <p
          id={"size-preview-#{@entry.ref}"}
          class="text-center text-xs text-zinc-700"
          phx-hook="image-size"
          data-target={"phx-preview-#{@entry.ref}"}
          phx-update="ignore"
        />
      </div>
    </div>
    """
  end

  @doc """
  Generates a datalist for the given options.
  """
  attr :id, :string, required: true
  attr :options, :list, required: true

  def datalist(assigns) do
    ~H"""
    <datalist id={@id}>
      <option :for={option <- @options} value={elem(option, 0)} />
    </datalist>
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
          {render_slot(@inner_block)}
        </h1>
        <p :if={@subtitle != []} class="mt-4 leading-6 text-zinc-800 dark:text-zinc-200">
          {render_slot(@subtitle)}
        </p>
      </div>
      <div class="flex-none">{render_slot(@actions)}</div>
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
  attr :rows, :list, required: true
  attr :row_id, :any, default: nil, doc: "the function for generating the row id"
  attr :row_click, :any, default: nil, doc: "the function for handling phx-click on each row"

  attr :row_item, :any,
    default: &Function.identity/1,
    doc: "the function for mapping each row before calling the :col and :action slots"

  slot :col, required: true do
    attr :label, :string
  end

  slot :action, doc: "the slot for showing user actions in the last table column"

  def table(assigns) do
    assigns =
      with %{rows: %Phoenix.LiveView.LiveStream{}} <- assigns do
        assign(assigns, row_id: assigns.row_id || fn {id, _item} -> id end)
      end

    ~H"""
    <div class="overflow-y-auto px-4 sm:overflow-visible sm:px-0">
      <table class="w-[40rem] mt-11 sm:w-full">
        <thead class="text-left text-sm leading-6 text-zinc-500">
          <tr>
            <th :for={col <- @col} class="p-0 pr-6 pb-4 font-normal">{col[:label]}</th>
            <th class="relative p-0 pb-4"><span class="sr-only">{gettext("Actions")}</span></th>
          </tr>
        </thead>
        <tbody
          id={@id}
          phx-update={match?(%Phoenix.LiveView.LiveStream{}, @rows) && "stream"}
          class="relative divide-y divide-zinc-100 border-t border-zinc-200 text-sm leading-6 text-zinc-700"
        >
          <tr :for={row <- @rows} id={@row_id && @row_id.(row)} class="group hover:bg-zinc-50">
            <td
              :for={{col, i} <- Enum.with_index(@col)}
              phx-click={@row_click && @row_click.(row)}
              class={["relative p-0", @row_click && "hover:cursor-pointer"]}
            >
              <div class="block py-4 pr-6">
                <span class="absolute -inset-y-px right-0 -left-4 group-hover:bg-zinc-50 sm:rounded-l-xl" />
                <span class={["relative", i == 0 && "font-semibold text-zinc-900"]}>
                  {render_slot(col, @row_item.(row))}
                </span>
              </div>
            </td>
            <td :if={@action != []} class="relative w-14 p-0">
              <div class="relative whitespace-nowrap py-4 text-right text-sm font-medium">
                <span class="absolute -inset-y-px -right-4 left-0 group-hover:bg-zinc-50 sm:rounded-r-xl" />
                <span
                  :for={action <- @action}
                  class="relative ml-4 font-semibold leading-6 text-zinc-900 hover:text-zinc-700"
                >
                  {render_slot(action, @row_item.(row))}
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
        <div :for={item <- @item} class="flex gap-4 py-4 text-sm leading-6 sm:gap-8">
          <dt class="w-1/4 flex-none text-zinc-500">{item.title}</dt>
          <dd class="text-zinc-700">{render_slot(item)}</dd>
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
        <FA.icon name="arrow-left" class="inline h-3 w-3 stroke-current" />
        {render_slot(@inner_block)}
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
    <.link class={["text-brand font-semibold hover:underline dark:text-brand-dark", @class]} {@rest} phx-no-format><%= render_slot(@inner_block) %></.link>
    """
  end

  @doc """
  Form card used to wrap the user auth forms.
  """
  slot :inner_block, required: true

  def auth_form_card(assigns) do
    ~H"""
    <div class="flex flex-col space-y-6 rounded-sm bg-white p-10 shadow-lg dark:bg-zinc-900">
      {render_slot(@inner_block)}
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
        <.title class="h-12" />
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
  Renders the Ambry title SVG.

  This is the text "Ambry" that appears next to the logo.

  ## Examples

      <.title class="h-12" />
  """
  attr :class, :string, default: nil

  def title(assigns) do
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
  attr :class, :string, default: nil
  slot :inner_block, required: true
  slot :label

  def note(assigns) do
    ~H"""
    <p class={["border-l-4 border-zinc-400 pl-4 italic text-zinc-500 dark:border-zinc-500 dark:text-zinc-400", @class]}>
      <%= if @label != [] do %>
        <strong>{render_slot(@label)}:</strong>
      <% else %>
        <strong>Note:</strong>
      <% end %>
      {render_slot(@inner_block)}
    </p>
    """
  end

  attr :id, :string, required: true
  attr :page, :integer, required: true
  attr :end?, :boolean, required: true
  attr :stream, :any, required: true
  attr :next, :string, default: "next-page"
  attr :prev, :string, default: "prev-page"
  attr :rest, :global

  def book_tiles_stream(assigns) do
    ~H"""
    <.grid
      id={@id}
      phx-update="stream"
      phx-viewport-top={@page > 1 && @prev}
      phx-viewport-bottom={!@end? && @next}
      phx-page-loading
      class={[if(@end?, do: "", else: "pb-[calc(200vh)]"), if(@page == 1, do: "", else: "pt-[calc(200vh)]")]}
      {@rest}
    >
      <.book_tile :for={{id, book} <- @stream} book={book} id={id} />
    </.grid>
    """
  end

  attr :id, :string, required: true
  attr :page, :integer, required: true
  attr :end?, :boolean, required: true
  attr :stream, :any, required: true
  attr :next, :string, default: "next-page"
  attr :prev, :string, default: "prev-page"
  attr :rest, :global

  def media_tiles_stream(assigns) do
    ~H"""
    <.grid
      id={@id}
      phx-update="stream"
      phx-viewport-top={@page > 1 && @prev}
      phx-viewport-bottom={!@end? && @next}
      phx-page-loading
      class={[if(@end?, do: "", else: "pb-[calc(200vh)]"), if(@page == 1, do: "", else: "pt-[calc(200vh)]")]}
      {@rest}
    >
      <.media_tile :for={{id, media} <- @stream} media={media} id={id} />
    </.grid>
    """
  end

  attr :id, :string, required: true
  attr :page, :integer, required: true
  attr :end?, :boolean, required: true
  attr :stream, :any, required: true
  attr :player, Player, required: true
  attr :next, :string, default: "next-page"
  attr :prev, :string, default: "prev-page"
  attr :rest, :global

  def player_state_tiles_stream(assigns) do
    ~H"""
    <.grid
      id={@id}
      phx-update="stream"
      phx-viewport-top={@page > 1 && @prev}
      phx-viewport-bottom={!@end? && @next}
      phx-page-loading
      class={[if(@end?, do: "", else: "pb-[calc(200vh)]"), if(@page == 1, do: "", else: "pt-[calc(200vh)]")]}
      {@rest}
    >
      <.player_state_tile :for={{id, player_state} <- @stream} player_state={player_state} player={@player} id={id} />
    </.grid>
    """
  end

  @doc """
  Renders a list of books as a responsive grid of image tiles.
  """
  attr :books, :list, required: true

  def book_tiles(assigns) do
    ~H"""
    <.grid>
      <.book_tile :for={{book, number} <- books_with_numbers(@books)} book={book} number={number} />
    </.grid>
    """
  end

  attr :id, :string, default: nil
  attr :book, Book, required: true
  attr :number, Decimal, default: nil

  def book_tile(assigns) do
    ~H"""
    <div id={@id} class="text-center">
      <%= if @number do %>
        <p class="font-bold text-zinc-900 dark:text-zinc-100 sm:text-lg">Book {@number}</p>
      <% end %>
      <div class="group">
        <.link navigate={~p"/books/#{@book}"}>
          <.book_multi_image thumbnails={Enum.flat_map(@book.media, &if(&1.thumbnails, do: [&1.thumbnails], else: []))} />
        </.link>
        <p class="font-bold text-zinc-900 group-hover:underline dark:text-zinc-100 sm:text-lg">
          <.link navigate={~p"/books/#{@book}"}>
            {@book.title}
          </.link>
        </p>
      </div>
      <p class="text-sm text-zinc-800 dark:text-zinc-200 sm:text-base">
        by <.people_links people={@book.authors} />
      </p>

      <div class="text-xs text-zinc-600 dark:text-zinc-400 sm:text-sm">
        <.series_book_links series_books={@book.series_books} />
      </div>
    </div>
    """
  end

  @doc """
  Renders a list of media as a responsive grid of image tiles.
  """
  attr :media, :list, required: true

  attr :rest, :global,
    include: ~w(show_title show_authors show_series show_narrators show_published)

  def media_tiles(assigns) do
    ~H"""
    <.grid>
      <.media_tile :for={media <- @media} media={media} {@rest} />
    </.grid>
    """
  end

  attr :id, :string, default: nil
  attr :media, Media, required: true

  attr :show_title, :boolean, default: true
  attr :show_authors, :boolean, default: true
  attr :show_series, :boolean, default: true
  attr :show_narrators, :boolean, default: false
  attr :show_published, :boolean, default: false

  def media_tile(assigns) do
    ~H"""
    <div id={@id} class="text-center">
      <div class="group">
        <.link navigate={~p"/audiobooks/#{@media}"}>
          <.book_multi_image thumbnails={if @media.thumbnails, do: [@media.thumbnails], else: []} />
        </.link>
        <p :if={@show_title} class="font-bold text-zinc-900 group-hover:underline dark:text-zinc-100 sm:text-lg">
          <.link navigate={~p"/audiobooks/#{@media}"}>
            {@media.book.title}
          </.link>
        </p>
      </div>

      <p :if={@show_authors} class="text-sm text-zinc-800 dark:text-zinc-200 sm:text-base">
        by <.people_links people={@media.book.authors} />
      </p>

      <p :if={@show_narrators} class="text-sm text-zinc-800 dark:text-zinc-200 sm:text-base">
        Narrated by <.people_links people={@media.narrators} full_cast={@media.full_cast} />
      </p>

      <div :if={@show_series} class="text-xs text-zinc-600 dark:text-zinc-400 sm:text-sm">
        <.series_book_links series_books={@media.book.series_books} />
      </div>

      <div :if={@show_published && @media.published} class="text-xs text-zinc-600 dark:text-zinc-400 sm:text-sm">
        Published {format_published(@media)}
        <p :if={@media.publisher}>
          by {@media.publisher}
        </p>
      </div>
    </div>
    """
  end

  attr :thumbnails, :list, required: true

  def book_multi_image(%{thumbnails: []} = assigns) do
    ~H"""
    <span class="block aspect-1 h-full w-full bg-zinc-100 dark:bg-zinc-900" />
    """
  end

  def book_multi_image(%{thumbnails: [thumbnail]} = assigns) do
    assigns = assign(assigns, :thumbnail, thumbnail)

    ~H"""
    <span class="block aspect-1">
      <img src={@thumbnail.large} class="h-full w-full object-cover object-center" />
    </span>
    """
  end

  def book_multi_image(%{thumbnails: [thumbnail1, thumbnail2]} = assigns) do
    assigns = assign(assigns, thumbnail1: thumbnail1, thumbnail2: thumbnail2)

    ~H"""
    <span class="relative block aspect-1">
      <img
        src={@thumbnail2.large}
        class={["h-full w-full object-cover object-center", "translate-x-1 translate-y-1", "scale-95"]}
      />
      <img
        src={@thumbnail1.large}
        class={[
          "absolute top-0 h-full w-full object-cover object-center",
          "border border-zinc-200 shadow-md dark:border-zinc-800",
          "-translate-x-1 -translate-y-1",
          "scale-95"
        ]}
      />
    </span>
    """
  end

  def book_multi_image(%{thumbnails: [thumbnail1, thumbnail2, thumbnail3 | _rest]} = assigns) do
    assigns =
      assign(assigns, thumbnail1: thumbnail1, thumbnail2: thumbnail2, thumbnail3: thumbnail3)

    ~H"""
    <span class="relative block aspect-1">
      <img
        src={@thumbnail3.large}
        class={["h-full w-full object-cover object-center", "translate-x-2 translate-y-2", "scale-90"]}
      />
      <img
        src={@thumbnail2.large}
        class={[
          "absolute top-0 h-full w-full object-cover object-center",
          "border border-zinc-200 shadow-md dark:border-zinc-800",
          "scale-90"
        ]}
      />
      <img
        src={@thumbnail1.large}
        class={[
          "absolute top-0 h-full w-full object-cover object-center",
          "border border-zinc-200 shadow-md dark:border-zinc-800",
          "-translate-x-2 -translate-y-2",
          "scale-90"
        ]}
      />
    </span>
    """
  end

  defp books_with_numbers(books_assign) do
    case books_assign do
      [] -> []
      [%Book{} | _] = books -> Enum.map(books, &{&1, nil})
      [%SeriesBook{} | _] = series_books -> Enum.map(series_books, &{&1.book, &1.book_number})
    end
  end

  attr :id, :string, default: nil
  attr :player_state, PlayerState, required: true
  attr :player, Player, required: true

  def player_state_tile(assigns) do
    ~H"""
    <div id={@id} class="text-center">
      <div class="group">
        <div class="aspect-w-1 aspect-h-1 relative">
          <.book_multi_image thumbnails={if @player_state.media.thumbnails, do: [@player_state.media.thumbnails], else: []} />
          <div class="absolute flex">
            <div
              phx-click={media_click_action(@player, @player_state.media)}
              class="mx-auto flex h-16 w-16 cursor-pointer self-center rounded-full bg-white bg-opacity-80 shadow-md backdrop-blur-sm transition group-hover:bg-opacity-100 dark:bg-black dark:bg-opacity-80"
            >
              <div class="mx-auto self-center fill-current">
                <%= if playing?(@player, @player_state.media) do %>
                  <FA.icon name="pause" class="h-7 w-7" />
                <% else %>
                  <FA.icon name="play" class="h-7 w-7 pl-1" />
                <% end %>
              </div>
            </div>
          </div>
        </div>
        <div class="overflow-hidden rounded-b-sm border-x border-zinc-200 bg-zinc-300 shadow-sm dark:border-zinc-900 dark:bg-zinc-800">
          <div class="bg-brand h-1 dark:bg-brand-dark" style={"width: #{progress_percent(@player, @player_state)}%;"} />
        </div>
      </div>
      <p class="font-bold text-zinc-900 hover:underline dark:text-zinc-100 sm:text-lg">
        <.link navigate={~p"/audiobooks/#{@player_state.media}"}>
          {@player_state.media.book.title}
        </.link>
      </p>
      <p class="text-sm text-zinc-800 dark:text-zinc-200 sm:text-base">
        by <.people_links people={@player_state.media.book.authors} />
      </p>

      <p class="text-sm text-zinc-800 dark:text-zinc-200 sm:text-base">
        Narrated by <.people_links people={@player_state.media.narrators} full_cast={@player_state.media.full_cast} />
      </p>

      <div class="text-xs text-zinc-600 dark:text-zinc-400 sm:text-sm">
        <.series_book_links series_books={@player_state.media.book.series_books} />
      </div>
    </div>
    """
  end

  defp media_click_action(player, media) do
    if loaded?(player, media) do
      JS.dispatch("ambry:toggle-playback", to: "#media-player")
    else
      "ambry:load-and-play-media"
      |> JS.dispatch(to: "#media-player", detail: %{id: media.id})
      |> JS.navigate(~p"/")
    end
  end

  defp loaded?(%Player{player_state: %{media_id: media_id}}, %Media{id: media_id}), do: true
  defp loaded?(_player, _media), do: false

  defp playing?(%Player{player_state: %{media_id: media_id}, playback_state: :playing}, %Media{
         id: media_id
       }),
       do: true

  defp playing?(_player, _media), do: false

  def progress_percent(%Player{player_state: %{id: id} = ps}, %PlayerState{id: id}) do
    progress_percent(ps)
  end

  def progress_percent(_player, ps) do
    progress_percent(ps)
  end

  def progress_percent(nil), do: "0.0"

  def progress_percent(%PlayerState{position: position, media: %{duration: duration}}) do
    position
    |> Decimal.div(duration)
    |> Decimal.mult(100)
    |> Decimal.round(1)
    |> Decimal.to_string()
  end

  @doc """
  Renders a list of links to people (like authors or narrators) separated by
  commas.

  Supports a `full_cast` option to print "and a full cast" at the end.
  """
  attr :people, :list, required: true
  attr :full_cast, :boolean, default: false

  def all_people_links(%{people: [], full_cast: true} = assigns) do
    ~H"a full cast"
  end

  def all_people_links(%{people: [], full_cast: false} = assigns) do
    ~H""
  end

  def all_people_links(assigns) do
    ~H"""
    <%= for person_ish <- @people do %>
      <.link navigate={~p"/people/#{person_ish.person_id}"} class="hover:underline" phx-no-format>
        <%= person_ish.name %></.link><span
        class="last:hidden"
        phx-no-format
      >,</span>
    <% end %>
    <span :if={@full_cast}>and a full cast</span>
    """
  end

  @doc """
  Renders a list of links to people (like authors or narrators) separated by
  commas.

  Limits to 2 people, then shows the count of the remaining people.

  Supports a `full_cast` option to print "and a full cast" at the end.
  """
  attr :people, :list, required: true
  attr :full_cast, :boolean, default: false

  def people_links(%{people: [], full_cast: true} = assigns) do
    ~H"a full cast"
  end

  def people_links(%{people: [], full_cast: false} = assigns) do
    ~H""
  end

  def people_links(%{people: [person], full_cast: true} = assigns) do
    assigns = assign(assigns, person: person)

    ~H"""
    <.link navigate={~p"/people/#{@person.person_id}"} class="hover:underline" phx-no-format>
    <%= @person.name %></.link><span phx-no-format>, and a full cast</span>
    """
  end

  def people_links(%{people: [person], full_cast: false} = assigns) do
    assigns = assign(assigns, person: person)

    ~H"""
    <.link navigate={~p"/people/#{@person.person_id}"} class="hover:underline">
      {@person.name}
    </.link>
    """
  end

  def people_links(%{people: [person1, person2], full_cast: true} = assigns) do
    assigns = assign(assigns, person1: person1, person2: person2)

    ~H"""
    <.link navigate={~p"/people/#{@person1.person_id}"} class="hover:underline" phx-no-format>
      <%= @person1.name %></.link><span phx-no-format>,</span>
    <.link navigate={~p"/people/#{@person2.person_id}"} class="hover:underline" phx-no-format>
      <%= @person2.name %></.link><span phx-no-format>, and a full cast</span>
    """
  end

  def people_links(%{people: [person1, person2], full_cast: false} = assigns) do
    assigns = assign(assigns, person1: person1, person2: person2)

    ~H"""
    <.link navigate={~p"/people/#{@person1.person_id}"} class="hover:underline" phx-no-format>
      <%= @person1.name %></.link><span phx-no-format>,</span>
    <.link navigate={~p"/people/#{@person2.person_id}"} class="hover:underline">
      {@person2.name}
    </.link>
    """
  end

  def people_links(%{people: [person1, person2 | rest], full_cast: true} = assigns) do
    assigns = assign(assigns, person1: person1, person2: person2, others: Enum.count(rest))

    ~H"""
    <.link navigate={~p"/people/#{@person1.person_id}"} class="hover:underline" phx-no-format>
      <%= @person1.name %></.link><span phx-no-format>,</span>
    <.link navigate={~p"/people/#{@person2.person_id}"} class="hover:underline" phx-no-format>
      <%= @person2.name %></.link><span phx-no-format>, <%= @others %> others, and a full cast</span>
    """
  end

  def people_links(%{people: [person1, person2 | rest], full_cast: false} = assigns) do
    assigns = assign(assigns, person1: person1, person2: person2, others: Enum.count(rest))

    ~H"""
    <.link navigate={~p"/people/#{@person1.person_id}"} class="hover:underline" phx-no-format>
      <%= @person1.name %></.link><span phx-no-format>,</span>
    <.link navigate={~p"/people/#{@person2.person_id}"} class="hover:underline" phx-no-format>
      <%= @person2.name %></.link><span phx-no-format>, and <%= @others %> others</span>
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
          {series_book.series.name} #{series_book.book_number}
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
    <h1 class="mb-6 text-3xl font-bold text-zinc-900 dark:text-zinc-100 md:mb-8 md:text-4xl lg:mb-12 lg:text-5xl">
      {render_slot(@inner_block)}
    </h1>
    """
  end

  @doc """
  A flexible grid of things
  """
  attr :class, :any, default: nil
  attr :rest, :global
  slot :inner_block, required: true

  def grid(assigns) do
    ~H"""
    <div class={["grid grid-cols-2 gap-4 sm:grid-cols-3 sm:gap-6 md:grid-cols-4 md:gap-8 xl:grid-cols-6", @class]} {@rest}>
      {render_slot(@inner_block)}
    </div>
    """
  end

  attr :content, :string, required: true
  attr :class, :string, default: nil

  def markdown(assigns) do
    ~H"""
    <article class={["prose prose-zinc dark:prose-invert", @class]}>
      {raw(Earmark.as_html!(@content))}
    </article>
    """
  end

  def menu_wrapper(assigns) do
    ~H"""
    <div
      id={@id}
      class="max-w-80 bg-zinc-50/90 absolute top-12 right-4 z-50 hidden text-zinc-800 shadow-md backdrop-blur transition-opacity dark:bg-zinc-900/90 dark:text-zinc-200"
    >
      <div class="h-full w-full divide-y divide-zinc-200 rounded-sm border border-zinc-200 dark:divide-zinc-800 dark:border-zinc-800">
        <div class="flex items-center gap-4 p-4">
          <img class="h-10 w-10 rounded-full" src={gravatar_url(@user.email)} />
          <p class="overflow-hidden text-ellipsis whitespace-nowrap">{@user.email}</p>
        </div>
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  attr :book, Book, required: true
  attr :class, :string, default: nil

  def book_header(assigns) do
    ~H"""
    <div>
      <h1 class={["text-3xl font-bold text-zinc-900 dark:text-zinc-100 sm:text-4xl", @class]}>
        {@book.title}
      </h1>
      <p class="text-zinc-800 dark:text-zinc-200 sm:text-lg xl:text-xl">
        <span>by <.all_people_links people={@book.authors} /></span>
      </p>

      <div class="text-sm text-zinc-600 dark:text-zinc-400 sm:text-base">
        <.series_book_links series_books={@book.series_books} />
      </div>
    </div>
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

  def toggle_menu(js \\ %JS{}, id) do
    JS.toggle(js,
      to: "##{id}",
      time: 100,
      in: transition_in(),
      out: transition_out()
    )
  end

  def hide_menu(js \\ %JS{}, id) do
    JS.hide(js,
      to: "##{id}",
      time: 100,
      transition: transition_out()
    )
  end

  def transition_in do
    {"transition-all transform ease-out duration-300",
     "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95",
     "opacity-100 translate-y-0 sm:scale-100"}
  end

  def transition_out do
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
    #     # Translate the number of files with plural rules
    #     dngettext("errors", "1 file", "%{count} files", count)
    #
    # However the error messages in our forms and APIs are generated
    # dynamically, so we need to translate them by calling Gettext
    # with our gettext backend as first argument. Translations are
    # available in the errors.po file (as we use the "errors" domain).
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

  def format_published(%{published: nil}), do: nil

  def format_published(%{published_format: :full, published: date}),
    do: Calendar.strftime(date, "%B %-d, %Y")

  def format_published(%{published_format: :year_month, published: date}),
    do: Calendar.strftime(date, "%B %Y")

  def format_published(%{published_format: :year, published: date}),
    do: Calendar.strftime(date, "%Y")

  def format_published(%{published_format: :full, published: date}, :short),
    do: Calendar.strftime(date, "%x")

  def format_published(%{published_format: :year_month, published: date}, :short),
    do: Calendar.strftime(date, "%Y-%m")

  def format_published(%{published_format: :year, published: date}, :short),
    do: Calendar.strftime(date, "%Y")
end
