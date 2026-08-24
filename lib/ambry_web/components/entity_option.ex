defmodule AmbryWeb.Components.EntityOption do
  @moduledoc """
  One row of a picker's list, and the option shape behind it.

  Two controls draw this row, `AmbryWeb.Components.EntityResolver` and
  `AmbryWeb.Components.EntityDropdown`, so a row of one is indistinguishable
  from a row of the other. Left to draw their own, two lists of audiobooks end
  up with the cover in different places.

  ## The option shape

  Plain `{label, id}` tuples, or maps for richer rows:

      %{id: 1, label: "A Court of Thorns and Roses", image: "/path.webp",
        detail: "GraphicAudio · 2022"}

  `image` renders a thumbnail and `detail` a muted second line, where the
  disambiguation lives so labels stay short. `trailer` is a muted aside on the
  label's own line, for the one fact separating two same-titled records when
  the detail line is full.

  `shape: :round` for a person, `:square` (the default) for anything with a
  cover; a portrait is a circle everywhere else in the app. Round ones anchor
  `object-top`, because a square crop of a tall portrait takes the chin.

  Where any option has an image, imageless rows hold the space with an empty
  tinted shape. **Not a letter**: the app has no lettered-avatar idiom. The
  tint is translucent, because the row sits on two grounds (`zinc-800` in the
  list, `zinc-700` when hovered) and any fixed step disappears into one.

  An option may also carry `query`: **what the record is found by, when that
  differs from how it is displayed.** Only the resolver reads it, but it
  belongs to the option, so contexts build one shape for both controls.
  """

  use Phoenix.Component

  import AmbryWeb.CoreComponents, only: [icon: 1]

  @defaults %{image: nil, detail: nil, trailer: nil, query: nil, shape: :square}

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
  is chosen. The `<li>` around it belongs to the caller, since the two
  controls differ in what makes a row clickable.
  """
  def option_row(assigns) do
    ~H"""
    <div class="flex min-w-0 items-center gap-2.5">
      <img
        :if={@option.image}
        src={@option.image}
        class={["h-9 w-9 flex-none object-cover", shape_classes(@option.shape)]}
        loading="lazy"
        alt=""
      />
      <span
        :if={!@option.image && @imaged}
        class={["bg-white/10 h-9 w-9 flex-none", shape_classes(@option.shape)]}
      />
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

  defp shape_classes(:round), do: "rounded-full object-top"
  defp shape_classes(_square), do: "rounded-sm"
end
