defmodule Marionette.Supervisor do
  @moduledoc false

  use Supervisor

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    {mktemp_out, 0} = System.cmd("mktemp", ["-d"])
    tmp_dir = String.trim(mktemp_out)

    children = [
      # Headless Firefox for scraping
      {MuonTrap.Daemon,
       [
         "firefox",
         ["--marionette", "--headless", "--no-remote", "--profile", tmp_dir],
         [
           name: FirefoxHeadless,
           log_output: :info,
           log_prefix: "[Firefox] ",
           stderr_to_stdout: true
         ]
       ]},
      # Socket for sending commands to the browser
      Marionette.Socket
    ]

    Supervisor.init(children, strategy: :rest_for_one)
  end
end
