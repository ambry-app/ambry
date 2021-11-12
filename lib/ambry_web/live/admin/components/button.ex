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
    transition-colors
    focus:outline-none
    focus:ring-2
    disabled:bg-gray-400
  )

  @color_classes %{
    yellow: ~w(
      bg-yellow-500
      hover:bg-yellow-700
      focus:ring-yellow-300
    ),
    red: ~w(
      bg-red-500
      hover:bg-red-700
      focus:ring-red-300
    )
  }

  prop label, :string, required: true
  prop click, :event, required: true
  prop color, :atom, default: :yellow
  prop class, :string, default: ""
  prop values, :list, default: []

  def render(assigns) do
    ~F"""
    <button :on-click={@click} :values={@values} class={@class <> " " <> classes(@color)}>
      {@label}
    </button>
    """
  end

  defp classes(color) do
    @classes |> Enum.concat(@color_classes[color]) |> Enum.join(" ")
  end
end
