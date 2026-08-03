defmodule Ambry.Media.RunReconciliation do
  @moduledoc """
  The periodic sweep that notices vanished files.

  Deliberately not `max_attempts: 1` like the other media workers: a sweep
  that failed because a NAS was briefly unreachable is worth retrying, and
  unlike a scan or a probe it has no side effect that could be applied twice.
  """

  use Oban.Worker,
    queue: :media,
    max_attempts: 3

  alias Ambry.Media.Reconciliation

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    {:ok, counts} = Reconciliation.reconcile_all()

    if counts.missing > 0 or counts.healed > 0 do
      Logger.info(fn -> "Reconciliation: #{inspect(counts)}" end)
    end

    {:ok, counts}
  end
end
