defmodule AmbryWeb.HeaderLive.Header.Player.Components do
  @moduledoc false

  use AmbryWeb, :p_component

  import AmbryWeb.TimeUtils, only: [format_timecode: 1]

  # prop playback_rate, :decimal, required: true
  # prop click, :event, required: true

  def playback_rate_button(assigns) do
    {click, target} = assigns.click

    ~H"""
    <button
      class="mx-auto border border-gray-300 rounded-md text-sm font-medium py-0.5 px-2 text-gray-500"
      phx-click={click}
      phx-target={target}
    >
      <%= format_decimal(@playback_rate) %>x
    </button>
    """
  end

  # prop playback_rate, :decimal, required: true
  # prop dismiss, :event, required: true

  def playback_rate_modal(assigns) do
    ~H"""
    <.simple_modal dismiss={@dismiss}>
      <h3 class="text-lg font-bold mb-2">
        Playback Speed
      </h3>
      <p class="text-center font-bold pb-4">
        <%= format_decimal(@playback_rate) %>x
      </p>
      <div class="pb-4">
        <input
          id="speed-slider"
          phx-hook="speedSlider"
          type="range"
          min="0.5"
          max="3.0"
          step="0.05"
          value={format_decimal(@playback_rate)}
          class="playback-speed-slider appearance-none w-full h-2 rounded-full bg-gray-200 outline-none shadow-inner"
        />
      </div>
      <div class="flex space-x-4 tabular-nums">
        <.rate_button rate="1.0" />
        <.rate_button rate="1.25" />
        <.rate_button rate="1.5" />
        <.rate_button rate="1.75" />
        <.rate_button rate="2.0" />
      </div>
    </.simple_modal>
    """
  end

  # prop :rate, :string, required: true

  defp rate_button(assigns) do
    ~H"""
    <button @click={"mediaPlayer.setPlaybackRate(#{@rate})"} class="rounded border border-gray-200 bg-gray-50 grow">
      <%= @rate %>x
    </button>
    """
  end

  # Show at least one decimal place, even if it's zero.
  defp format_decimal(decimal) do
    rounded = Decimal.round(decimal, 1)

    if Decimal.equal?(rounded, decimal), do: rounded, else: decimal
  end

  # prop click, :event, required: true

  def chapters_button(assigns) do
    {click, target} = assigns.click

    ~H"""
    <button phx-click={click} phx-target={target}>
      <Heroicons.Outline.collection />
    </button>
    """
  end

  # prop chapters, :list, required: true
  # prop dismiss, :event, required: true

  def chapters_modal(assigns) do
    ~H"""
    <.simple_modal dismiss={@dismiss}>
      <h3 class="text-lg font-bold mb-2">
        Chapters
      </h3>
      <div class="mt-8 divide-y divide-gray-200">
        <%= if @chapters == [] do %>
          <p class="font-semibold">
            This book has no chapters defined.
          </p>
        <% else %>
          <%= for chapter <- @chapters do %>
            <div class="p-2 flex items-center">
              <a href="#" class="mr-1" onClick={"mediaPlayer.seek(#{chapter.time})"}>
                <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5" viewBox="0 0 20 20" fill="currentColor">
                  <path
                    fill-rule="evenodd"
                    d="M10 18a8 8 0 100-16 8 8 0 000 16zm1-12a1 1 0 10-2 0v4a1 1 0 00.293.707l2.828 2.829a1 1 0 101.415-1.415L11 9.586V6z"
                    clip-rule="evenodd"
                  />
                </svg>
              </a>
              <div class="w-20 pr-2 tabular-nums text-gray-500 italic">
                <a href="#" onClick={"mediaPlayer.seek(#{chapter.time})"}>
                  <%= format_timecode(chapter.time) %>
                </a>
              </div>
              <div class="grow">
                <a href="#" onClick={"mediaPlayer.seek(#{chapter.time})"}>
                  <%= chapter.title %>
                </a>
              </div>
            </div>
          <% end %>
        <% end %>
      </div>
    </.simple_modal>
    """
  end

  # prop click, :event, required: true

  def bookmarks_button(assigns) do
    {click, target} = assigns.click

    ~H"""
    <button phx-click={click} phx-target={target}>
      <Heroicons.Outline.bookmark />
    </button>
    """
  end

  # prop :dismiss, :event, required: true

  def simple_modal(assigns) do
    {dismiss, target} = assigns.dismiss

    ~H"""
    <div
      phx-window-keydown={dismiss}
      phx-target={target}
      phx-key="escape"
      class="fixed z-10 inset-0 overflow-y-auto"
    >
      <div class="flex items-end justify-center min-h-screen pt-4 px-4 pb-20 text-center sm:block sm:p-0">
        <div class="fixed inset-0 bg-gray-500 bg-opacity-75" />

        <%# This element is to trick the browser into centering the modal contents. %>
        <span class="hidden sm:inline-block sm:align-middle sm:h-screen">&#8203;</span>

        <%# Content %>
        <div
          class="inline-block align-bottom bg-white rounded-lg text-left overflow-hidden shadow-xl transform sm:my-8 sm:align-middle sm:max-w-lg w-full"
          phx-click-away={dismiss}
          phx-target={target}
        >
          <div class="bg-white px-4 pt-5 pb-4 sm:p-6 sm:pb-4">
            <%= render_slot(@inner_block) %>
          </div>
          <div class="bg-gray-50 px-4 py-3 sm:px-6 sm:flex sm:flex-row-reverse">
            <button
              class="text-white font-bold w-full inline-flex justify-center rounded shadow px-5 py-2 sm:ml-3 sm:w-auto bg-lime-500 hover:bg-lime-700 focus:outline-none transition-colors focus:ring-2 focus:ring-lime-300"
              phx-click={dismiss}
              phx-target={target}
            >
              Ok
            </button>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
