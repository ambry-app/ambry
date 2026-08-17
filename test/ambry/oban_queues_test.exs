defmodule Ambry.ObanQueuesTest do
  @moduledoc """
  Every worker's queue has to exist, or its jobs sit in the database forever.

  Oban accepts an insert into a queue nothing is running — there is no
  producer to refuse it — so the failure is silent and looks exactly like a
  feature that stopped working for no reason. Removing the `media` queue
  during the transcode retirement did this to discovery, probing, importing,
  organizing, reconciliation and publish-pending in one line, and the whole
  suite stayed green because tests drain queues by name.
  """
  use ExUnit.Case, async: true

  @configured Enum.map(Application.compile_env!(:ambry, Oban)[:queues], fn {name, _} -> name end)

  test "every Oban worker runs on a configured queue" do
    unconfigured =
      for {module, _} <- workers(),
          queue = module.__opts__()[:queue],
          queue not in @configured,
          do: {module, queue}

    assert unconfigured == [], """
    These workers name a queue that isn't configured, so their jobs would
    never run:

    #{Enum.map_join(unconfigured, "\n", fn {module, queue} -> "  #{inspect(module)} → #{inspect(queue)}" end)}

    Configured queues: #{inspect(@configured)}
    """
  end

  test "every cron entry names a real worker" do
    crontab =
      :ambry
      |> Application.get_env(Oban)
      |> Keyword.fetch!(:plugins)
      |> Enum.find_value(fn
        {Oban.Plugins.Cron, opts} -> opts[:crontab]
        _plugin -> nil
      end)

    for {_schedule, worker} <- crontab do
      assert Code.ensure_loaded?(worker), "#{inspect(worker)} is scheduled but does not exist"
      assert function_exported?(worker, :perform, 1), "#{inspect(worker)} is not an Oban worker"
    end
  end

  # Every module the app ships that `use Oban.Worker`.
  defp workers do
    {:ok, modules} = :application.get_key(:ambry, :modules)

    for module <- modules,
        Code.ensure_loaded?(module),
        function_exported?(module, :__opts__, 0),
        function_exported?(module, :perform, 1),
        do: {module, module.__opts__()}
  end
end
