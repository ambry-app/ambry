defmodule AmbryScraping.Marionette.Supervisor do
  @moduledoc false

  use Supervisor

  alias AmbryScraping.Marionette

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl Supervisor
  def init(_init_arg) do
    case Application.fetch_env(:ambry, Marionette.Connection) do
      :error ->
        :ignore

      {:ok, config} ->
        children = [
          # Connection for sending commands to the browser
          {Marionette.Connection, config},
          # Higher-level interface for serializing commands to the browser
          Marionette.Browser
        ]

        Supervisor.init(children, strategy: :rest_for_one)
    end
  end
end
