defmodule Ambry.Provenance do
  @moduledoc """
  Field-level metadata provenance and locks.

  Every provider-fillable scalar field on a schema records where its current
  value came from and whether it's locked against automated overwrite. The
  provenance lives in a `field_provenance` jsonb map on the record itself,
  keyed by field name:

      %{"description" => %{"source" => "provider:audible", "locked" => false, "at" => "..."}}

  Sources:

    * `"manual"` — the operator typed/edited the value. Always locked.
    * `"provider:<id>"` — an accepted metadata-provider suggestion. Unlocked,
      so future refresh may update it; accepting a suggestion is a choice of
      source, not curation of the value itself.
    * `"legacy"` — a value that predates provenance tracking (set by the
      backfill migration, locked) or had no recorded origin when it was
      first locked.

  Locks gate **automated writers only** (the future inbox approval and
  background refresh — they must route their updates through
  `reject_locked/2`). Operator-driven forms may always write any field; what
  varies is the provenance they record: schemas call `track_changes/3` from
  their changeset with the per-field source hints the form collected, and
  any tracked change without a hint is a manual edit — locked.

  Each schema owns its tracked-field list (its provider-fillable scalars)
  and passes it in; structural associations are operator-owned by definition
  and never carry provenance.
  """

  import Ecto.Changeset

  alias Ambry.Repo

  @manual "manual"
  @legacy "legacy"

  @type source :: String.t()
  @type entry :: %{String.t() => String.t() | boolean()}

  @doc "The provenance source string for a metadata provider id."
  @spec provider_source(String.t()) :: source()
  def provider_source(provider_id) when is_binary(provider_id), do: "provider:" <> provider_id

  @doc "The provenance entry for a field, or nil if none was ever recorded."
  @spec entry(struct(), atom() | String.t()) :: entry() | nil
  def entry(record, field) do
    Map.get(record.field_provenance || %{}, to_string(field))
  end

  @doc "Whether a field is locked against automated overwrite."
  @spec locked?(struct(), atom() | String.t()) :: boolean()
  def locked?(record, field) do
    match?(%{"locked" => true}, entry(record, field))
  end

  @doc """
  Records provenance for every tracked field the changeset is changing.

  `sources` maps field names (strings) to the source the pending value came
  from (e.g. `"provider:audible"`); a changed field with a source hint
  records that source unlocked, a changed field without one is a manual
  edit — recorded `"manual"` and locked. Unchanged fields keep whatever
  provenance they had.
  """
  @spec track_changes(Ecto.Changeset.t(), [atom()], %{String.t() => source()}) ::
          Ecto.Changeset.t()
  def track_changes(%Ecto.Changeset{} = changeset, tracked_fields, sources) do
    existing = changeset.data.field_provenance || %{}

    updated =
      Enum.reduce(tracked_fields, existing, fn field, acc ->
        if Map.has_key?(changeset.changes, field) do
          Map.put(acc, to_string(field), new_entry(Map.get(sources, to_string(field))))
        else
          acc
        end
      end)

    if updated == existing do
      changeset
    else
      put_change(changeset, :field_provenance, updated)
    end
  end

  defp new_entry(nil), do: %{"source" => @manual, "locked" => true, "at" => now()}

  defp new_entry(source) when is_binary(source),
    do: %{"source" => source, "locked" => false, "at" => now()}

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()

  @doc """
  Drops every locked field from a proposed attrs map (string or atom keys).

  This is the gate all automated writers (inbox approval, background
  refresh, auto-match) must route proposed updates through before calling a
  context update function — it's what makes re-syncing facts safe for
  curated records. Operator-driven forms do NOT use this; explicit operator
  action may always write.
  """
  @spec reject_locked(struct(), map()) :: map()
  def reject_locked(record, attrs) when is_map(attrs) do
    locked_fields =
      for {field, %{"locked" => true}} <- record.field_provenance || %{}, do: field

    Map.drop(attrs, locked_fields ++ Enum.map(locked_fields, &String.to_existing_atom/1))
  end

  @doc """
  Flips a field's lock, persisting immediately.

  Locking a field that never had provenance recorded protects its current
  value under the `"legacy"` (unknown-origin) source. The lock flag is
  provenance metadata, not entity data — no search/broadcast side effects
  apply.
  """
  @spec toggle_lock(struct(), atom() | String.t()) :: {:ok, struct()} | {:error, term()}
  def toggle_lock(record, field) do
    field = to_string(field)
    current = entry(record, field) || %{"source" => @legacy, "at" => now()}
    updated_entry = Map.put(current, "locked", !current["locked"])
    updated_map = Map.put(record.field_provenance || %{}, field, updated_entry)

    record
    |> change(field_provenance: updated_map)
    |> Repo.update()
  end
end
