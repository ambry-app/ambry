defmodule AmbryWeb.HeaderLive.Header.Components do
  @moduledoc false

  use AmbryWeb, :p_component

  # prop playing, :boolean, default: false

  def play_button(assigns) do
    assigns = assign_new(assigns, :playing, fn -> false end)

    ~H"""
    <div class="cursor-pointer" onclick="mediaPlayer.playPause()">
      <svg class="w-9 sm:w-11" viewBox="0 0 50 50" fill="none">
        <circle class="text-gray-300" cx="25" cy="25" r="24" stroke="currentColor" stroke-width="1.5" />
        <%= if @playing do %>
          <!-- pause button -->
          <path d="M18 16h4v18h-4V16zM28 16h4v18h-4z" fill="currentColor" />
        <% else %>
          <!-- play button -->
          <path d="M20 16l14 9l-14 9z" fill="currentColor" />
        <% end %>
      </svg>
    </div>
    """
  end

  # prop change, :event, required: true
  # prop close, :event, required: true
  # prop query, :string, required: true

  def search_form(assigns) do
    opts = [
      autocomplete: "off",
      "x-data": "{}",
      "@submit.prevent": "$el.lastElementChild.click()"
    ]

    ~H"""
    <.form let={f} for={:search} phx-change={@change} {opts}>
      <.search_input form={f} field={:query} placeholder="Search..." class="h-8 w-52 !rounded-full" />
      <%= if is_binary(@query) && String.trim(@query) != "" do %>
        <a
          class="hidden"
          data-phx-link="redirect"
          data-phx-link-state="push"
          phx-click={@close}
          href={Routes.search_results_path(AmbryWeb.Endpoint, :results, String.trim(@query))}
        />
      <% end %>
    </.form>
    """
  end

  # prop email, :string, required: true

  def gravatar(assigns) do
    ~H"""
    <img class="h-10 sm:h-12 mr-2 rounded-full shadow-md" src={gravatar_url(@email)} />
    """
  end

  def tiny_book_cover(assigns) do
    ~H"""
    <img
      src={@book.image_path}
      class="h-10 sm:h-12 object-center object-cover rounded shadow-md border border-gray-200"
    />
    """
  end
end
