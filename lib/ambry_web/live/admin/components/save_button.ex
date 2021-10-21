defmodule AmbryWeb.Admin.Components.SaveButton do
  @moduledoc """
  Renders a save button
  """

  use AmbryWeb, :component

  alias Surface.Components.Form.Submit

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
    bg-lime-500
    transition-colors
    hover:bg-lime-700
    focus:outline-none
    focus:ring-2
    focus:ring-lime-300
    disabled:bg-gray-400
  )

  def render(assigns) do
    ~F"""
    <Submit opts={"phx-disable-with": "Saving..."} class={classes()}>
      Save
    </Submit>
    """
  end

  defp classes do
    @classes
  end
end
