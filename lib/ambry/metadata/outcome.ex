defmodule Ambry.Metadata.Outcome do
  @moduledoc """
  What one provider actually did when asked, as the askers record it.

  Every fan-out reports one of these per provider, because "found nothing"
  and "couldn't be reached" must never look the same.

  A provider is asked more than one kind of question about a single item: a
  search, the details behind the hits it returned, the editions of the work it
  named. Those succeed and fail independently, and under one id the last one
  written wins, so a rate-limited details call disappears behind a search that
  already said `ok` and the record silently keeps the summary.

  So a kind other than `:search` gets its own id and its own chip:
  `hardcover` searched, `hardcover:details` hydrated, `hardcover:editions`
  listed editions. `Ambry.Inbox.unreached_providers/1` reads all of them, so
  any one failing sends `Ambry.Inbox.RunMatch` back around.
  """

  @kinds [:search, :details, :editions, :chapters]

  @doc "The outcome id a provider's answer of this kind is recorded under."
  def id(provider_id, kind \\ :search)
  def id(provider_id, :search), do: provider_id
  def id(provider_id, kind) when kind in @kinds, do: "#{provider_id}:#{kind}"

  @doc """
  Splits a recorded id back into the provider and what it was asked.

  The retry chip carries the id, and re-running a search when a details call
  failed would report success having fixed nothing.
  """
  def split(outcome_id) when is_binary(outcome_id) do
    case String.split(outcome_id, ":", parts: 2) do
      [provider_id, kind] when kind in ~w(details editions chapters) ->
        {provider_id, String.to_existing_atom(kind)}

      _search ->
        {outcome_id, :search}
    end
  end

  @doc "A provider answered."
  def ok(entry, count, kind \\ :search) do
    %{
      "id" => id(entry.id, kind),
      "name" => name(entry, kind),
      "status" => "ok",
      "count" => count
    }
  end

  @doc """
  A provider couldn't answer.

  The reason is kept short and human: enough to tell a rate limit from a bad
  token from an instance being down, without leaking an HTTP response into
  jsonb.
  """
  def failed(entry, reason, kind \\ :search) do
    %{
      "id" => id(entry.id, kind),
      "name" => name(entry, kind),
      "status" => "failed",
      "count" => 0,
      "reason" => describe(reason)
    }
  end

  @doc """
  A provider answered with part of what was asked of it.

  Some of what it was asked reached it and some did not. Regional catalogs
  are the case this exists for: one marketplace rate-limited while the others
  answered is otherwise indistinguishable from one with nothing in it.

  Recorded as a failure, deliberately: everything that reads these asks one
  question, whether a retry could still get something, and for a partial
  answer it could. It carries the count of what did come back, and the chip
  words itself off `partial`.
  """
  def partial(entry, count, reason, kind \\ :search) do
    entry
    |> failed(reason, kind)
    |> Map.merge(%{"count" => count, "partial" => true})
  end

  @doc "True if this outcome is a partial answer rather than nothing at all."
  def partial?(%{"partial" => true}), do: true
  def partial?(_outcome), do: false

  # A provider that cannot be asked, as opposed to one that couldn't be
  # reached. No request was made, so nothing a retry could change.
  @unaskable [:unsupported_capability, :provider_disabled, :provider_not_configured]

  # The provider answered, and the answer is that it has no such record. That
  # is "found nothing", which is a count of zero — not a failure.
  @answered [:not_found]

  @doc """
  What to record when a call comes back an error.

  Not every error is a failure to reach a provider: a call a provider does
  not implement was never made, and a 404 is a definite answer. Treating them
  alike puts a permanent "couldn't be reached, retry" chip on items whose
  retry could never succeed, and keeps
  `Ambry.Inbox.unreached_providers/1` non-empty so the matching job runs
  again for as long as it has attempts.

  Returns nil when there is nothing to say, so callers drop it.
  """
  def from_error(entry, reason, kind \\ :search)
  def from_error(_entry, reason, _kind) when reason in @unaskable, do: nil
  def from_error(entry, reason, kind) when reason in @answered, do: ok(entry, 0, kind)
  def from_error(entry, reason, kind), do: failed(entry, reason, kind)

  @doc "True if this outcome says the provider couldn't be reached."
  def failed?(%{"status" => "failed"}), do: true
  def failed?(_outcome), do: false

  @doc "Shortens a provider error to something a chip's tooltip can hold."
  def describe(reason) when is_binary(reason), do: String.slice(reason, 0, 200)
  def describe(reason), do: reason |> inspect() |> String.slice(0, 200)

  defp name(entry, :search), do: entry.display_name
  defp name(entry, :details), do: "#{entry.display_name} details"
  defp name(entry, :editions), do: "#{entry.display_name} editions"
  defp name(entry, :chapters), do: "#{entry.display_name} chapters"
end
