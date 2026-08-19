defmodule AmbryWeb.Components.EntityOption do
  @moduledoc """
  One row of a picker's list, and the option shape behind it.

  Two components draw this row — `AmbryWeb.Components.EntityResolver`, where
  you type and the server searches, and `AmbryWeb.Components.EntityDropdown`,
  where you click and choose from what's there. They are different controls
  answering the same question, so a row of one has to be indistinguishable
  from a row of the other; leaving each to draw its own is how two lists of
  audiobooks end up with the cover in different places.

  ## The option shape

  Plain `{label, id}` tuples, or maps for richer rows:

      %{id: 1, label: "A Court of Thorns and Roses", image: "/path.webp",
        detail: "GraphicAudio · 2022"}

  `image` renders a thumbnail (cover, portrait), `detail` a muted second
  line — the disambiguation lives there, so labels stay short. When any
  option in a list carries an image, imageless rows hold the space with a
  lettered placeholder so the column stays aligned. `trailer` is a muted
  aside on the label's own line, for the one fact that separates two
  same-titled records (a series and its number) when the detail line is
  already full.

  An option may also carry `query`: **what the record is found by, when that
  differs from how it is displayed.** Only the resolver reads it — a dropdown
  never searches — but it belongs to the option, not to the control, so
  contexts build one option shape for both.
  """

  use Phoenix.Component

  import AmbryWeb.CoreComponents, only: [icon: 1]

  @defaults %{image: nil, detail: nil, trailer: nil, query: nil}

  @doc """
  Fills in an option's optional keys, so a row can read them without guarding.
  """
  def normalize(nil), do: nil
  def normalize({label, id}), do: Map.merge(@defaults, %{id: id, label: label})
  def normalize(%{id: _id, label: _label} = option), do: Map.merge(@defaults, option)

  @doc """
  True when `value` names this option, whatever the two are spelled as.
  """
  def selected?(_option, nil), do: false
  def selected?(_option, ""), do: false
  def selected?(%{id: id}, value), do: to_string(id) == to_string(value)

  attr :option, :map, required: true
  attr :selected, :boolean, default: false

  attr :imaged, :boolean,
    default: false,
    doc: "true when some option in this list has an image, so imageless rows hold the column"

  @doc """
  The inside of one option row: thumbnail, label, and the marks that say what
  is chosen.

  The `<li>` around it belongs to the caller, because the two controls differ
  in what makes a row clickable.
  """
  def option_row(assigns) do
    ~H"""
    <div class="flex min-w-0 items-center gap-2.5">
      <img
        :if={@option.image}
        src={@option.image}
        class="h-9 w-9 flex-none rounded-sm object-cover"
        loading="lazy"
        alt=""
      />
      <span
        :if={!@option.image && @imaged}
        class="flex h-9 w-9 flex-none items-center justify-center rounded-sm bg-zinc-700 text-sm text-zinc-500"
      >
        {String.first(@option.label)}
      </span>
      <span class="min-w-0 grow">
        <%!-- Where it sits rides the label's line, muted, rather than
            joining a detail line already carrying five facts. No middle
            dot: the size and colour already separate it, so the dot was
            a second mark doing a job that was done. It gives way three
            times faster than the title when the row runs out of width,
            because meta truncates before content (§7). --%>
        <span class="flex min-w-0 items-baseline gap-1.5">
          <span class="min-w-0 shrink truncate">{@option.label}</span>
          <span :if={@option.trailer} class="shrink-[3] min-w-0 truncate text-xs text-zinc-500">
            {@option.trailer}
          </span>
        </span>
        <span :if={@option.detail} class="block truncate text-xs text-zinc-400">
          {@option.detail}
        </span>
      </span>
      <.icon :if={@selected} name="fa-check" class="text-brand-dark h-3.5 w-3.5 flex-none" />
    </div>
    """
  end
end
