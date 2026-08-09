defmodule AmbryWeb.Layouts do
  @moduledoc false

  use AmbryWeb, :html

  import AmbryWeb.Gravatar

  alias Ambry.Accounts.User
  alias AmbryWeb.Components.SearchBox

  embed_templates "layouts/*"

  @doc """
  Main app layout
  """

  attr :flash, :any, required: true
  attr :current_user, :any, required: true
  attr :nav_active_path, :any, required: true
  attr :query, :any, default: nil

  def app(assigns)

  @doc """
  Main app navigation header
  """

  attr :user, User, required: true
  attr :active_path, :string, required: true
  attr :query, :any, default: nil

  def nav_header(assigns) do
    ~H"""
    <header id="nav-header" class="border-zinc-900">
      <div class="flex p-4 text-zinc-500">
        <div class="flex-1">
          <.link navigate={~p"/"} class="flex">
            <.ambry_icon />
            <.ambry_title />
          </.link>
        </div>
        <div class="flex-1">
          <div class="flex justify-center gap-8 whitespace-nowrap lg:gap-12">
            <.link navigate={~p"/"} class={nav_class(@active_path in ["/", "/library"])}>
              <span title="Library"><.icon name="fa-book-open" class="mt-1 h-6 w-6 text-current lg:hidden" /></span>
              <span class="hidden text-xl font-bold lg:block">Library</span>
            </.link>
            <span
              phx-click={show_search()}
              class={nav_class(String.starts_with?(@active_path, "/search"), "flex cursor-pointer content-center gap-4")}
            >
              <span title="Search">
                <.icon name="fa-magnifying-glass" class="mt-1 h-6 w-6 text-current lg:h-5 lg:w-5" />
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

      <.live_component
        id="search-box"
        module={SearchBox}
        query={@query}
        is_open={search_open?(@active_path)}
        hide_search={hide_search()}
      />
    </header>
    """
  end

  defp search_open?("/search/" <> _query), do: true
  defp search_open?(_path), do: false

  @doc """
  Ambry logo icon
  """

  def ambry_icon(assigns) do
    ~H"""
    <svg
      class="text-brand-dark mt-1 h-6 w-6 lg:h-7 lg:w-7"
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
  Ambry logo text
  """

  def ambry_title(assigns) do
    ~H"""
    <svg
      class="mt-1 hidden h-6 text-zinc-100 md:block lg:h-7"
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

  defp nav_class(active?, extra \\ "")
  defp nav_class(true, extra), do: "text-zinc-100 #{extra}"
  defp nav_class(false, extra), do: "hover:text-zinc-100 #{extra}"

  attr :user, User, required: true

  defp user_menu(assigns) do
    ~H"""
    <.menu_wrapper id="user-menu" user={@user}>
      <div class="py-3">
        <%= if @user.admin do %>
          <.link navigate={~p"/admin"} class="flex items-center gap-4 px-4 py-2 hover:bg-zinc-700">
            <.icon name="fa-screwdriver-wrench" class="h-5 w-5 text-current" />
            <p>Admin</p>
          </.link>
        <% end %>
        <.link
          navigate={~p"/users/settings"}
          class="flex items-center gap-4 px-4 py-2 hover:bg-zinc-700"
        >
          <.icon name="fa-user-gear" class="h-5 w-5 text-current" />
          <p>Account Settings</p>
        </.link>
        <.link
          href={~p"/users/log_out"}
          method="delete"
          class="flex items-center gap-4 px-4 py-2 hover:bg-zinc-700"
        >
          <.icon name="fa-arrow-right-from-bracket" class="h-5 w-5 text-current" />
          <p>Log out</p>
        </.link>
      </div>
    </.menu_wrapper>
    """
  end

  ## JS Commands

  defp show_search(js \\ %JS{}) do
    js
    |> JS.show(
      to: "#search-box",
      time: 100,
      transition: transition_in()
    )
    |> JS.focus(to: "#search-input")
    |> JS.dispatch("ambry:search-box-shown", to: "#search-box")
  end

  defp hide_search(js \\ %JS{}) do
    js
    |> JS.hide(
      to: "#search-box",
      time: 100,
      transition: transition_out()
    )
    |> JS.dispatch("ambry:search-box-hidden", to: "#search-box")
  end
end
