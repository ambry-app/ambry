defmodule Ambry.Provenance do
  @moduledoc """
  Field-level metadata provenance and locks.

  Every provider-fillable scalar field records where its current value came
  from and whether it is locked, in a `field_provenance` jsonb map keyed by
  field name:

      %{"description" => %{"source" => "provider:audible", "locked" => false, "at" => "..."}}

    * `"manual"` — the operator typed it. Always locked.
    * `"provider:<id>"` — an accepted suggestion. Unlocked, so a refresh may
      update it: accepting is a choice of source, not curation of the value.
    * `"legacy"` — no recorded origin. Locked.

  Locks gate **automated writers only**, which route through
  `reject_locked/2`. Operator-driven forms may always write any field; what
  varies is the provenance recorded, via `track_changes/3` and the per-field
  source hints the form collected. A tracked change with no hint is manual.

  Each schema owns its tracked-field list. Structural associations are
  operator-owned by definition and never carry provenance.
  """

  import Ecto.Changeset

  @manual "manual"

  @type source :: String.t() | %{required(String.t()) => String.t()}
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
  Records provenance for the tracked fields a save touches.

  `sources` maps field names to where the pending value came from. A hinted
  field records that source unlocked, even where the accepted value equals
  what was stored: the acceptance is a statement about where the value comes
  from, and what lets a refresh update it later. A changed field with no hint
  is manual and locked; unchanged, unhinted fields keep what they had.
  """
  @spec track_changes(Ecto.Changeset.t(), [atom()], %{String.t() => source()}) ::
          Ecto.Changeset.t()
  def track_changes(%Ecto.Changeset{} = changeset, tracked_fields, sources) do
    existing = changeset.data.field_provenance || %{}

    updated =
      Enum.reduce(tracked_fields, existing, fn field, acc ->
        source = Map.get(sources, to_string(field))

        cond do
          Map.has_key?(changeset.changes, field) ->
            Map.put(acc, to_string(field), new_entry(source))

          source && get_field(changeset, field) not in [nil, ""] ->
            Map.put(acc, to_string(field), new_entry(source))

          true ->
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

  # A source that also names the provider record it came out of — the ref a
  # later evidence search recognizes ("this record filled the title").
  defp new_entry(%{"source" => source} = given) when is_binary(source) do
    case given["record"] do
      nil -> new_entry(source)
      record -> source |> new_entry() |> Map.put("record", to_string(record))
    end
  end

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()

  @doc """
  Drops every locked field from a proposed attrs map (string or atom keys).

  The gate every automated writer routes through before calling a context
  update, which is what makes re-syncing facts safe for curated records.
  Operator-driven forms do not use it: explicit action may always write.
  """
  @spec reject_locked(struct(), map()) :: map()
  def reject_locked(record, attrs) when is_map(attrs) do
    locked_fields =
      for {field, %{"locked" => true}} <- record.field_provenance || %{}, do: field

    Map.drop(attrs, locked_fields ++ Enum.map(locked_fields, &String.to_existing_atom/1))
  end
end
