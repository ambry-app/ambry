defmodule AmbryWeb.Admin.Components.Button do
  @moduledoc """
  Renders a button
  """

  use AmbryWeb, :component

  @classes ~w(
    text-white
    font-bold
    w-full
    inline-flex
    justify-center
    rounded
    shadow
    px-5
    py-2
    sm:ml-3
    sm:w-auto
    bg-yellow-500
    transition-colors
    hover:bg-yellow-700
    focus:outline-none
    focus:ring-2
    focus:ring-yellow-300
    disabled:bg-gray-400
  )

  prop label, :string, required: true
  prop click, :event, required: true

  def render(assigns) do
    ~F"""
    <button :on-click={@click} class={classes()}>
      {@label}
    </button>
    """
  end

  defp classes do
    @classes
  end
end
