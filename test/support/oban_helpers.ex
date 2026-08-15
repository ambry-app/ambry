defmodule Ambry.ObanHelpers do
  @moduledoc """
  Job rows in whatever state a test needs to see.

  Straight into `oban_jobs` rather than through `Oban.insert/1`, because the
  states worth asserting about are the ones Oban will not let you insert:
  `executing` is claimed by a running producer, and `discarded`/`cancelled`
  are outcomes. `config/test.exs` sets `testing: :manual`, so nothing here is
  ever picked up and run.
  """

  alias Ambry.Repo

  @defaults %{
    state: "available",
    queue: "default",
    worker: "Ambry.Inbox.RunProbe",
    args: %{},
    errors: [],
    attempt: 0,
    max_attempts: 20,
    inserted_at: ~N[2026-08-01 00:00:00],
    scheduled_at: ~N[2026-08-01 00:00:00]
  }

  @doc """
  Inserts one job row. Any column may be overridden; see `@defaults`.
  """
  def insert_job(attrs \\ []) do
    Repo.insert_all("oban_jobs", [Map.merge(@defaults, Map.new(attrs))])
  end
end
