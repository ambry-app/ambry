defmodule Ambry.Metadata.Outcome do
  @moduledoc """
  What one provider actually did when asked, as the askers record it.

  Every fan-out reports one of these per provider, because "found nothing"
  and "couldn't be reached" must never look the same — a rate-limited source
  otherwise reads as one that was never consulted.

  ## Why a call needs a kind

  A provider is asked more than one kind of question about a single item: a
  search, then the details behind the hits it returned, then the editions of
  the work it named. Those succeed and fail independently, and reporting them
  under one id meant the last one written won: a details call that was
  rate-limited disappeared behind the search that had already said `ok`, and
  the record silently kept the summary — no description, no cover, no
  edition list — with nothing anywhere saying so.

  So a kind other than `:search` gets its own id and its own chip:
  `hardcover` searched, `hardcover:details` hydrated, `hardcover:editions`
  listed editions. `Ambry.Inbox.unreached_providers/1` reads all of them, so
  any one of them failing is enough to send `Ambry.Inbox.RunMatch` back
  around — which is the whole point, since provider errors are never cached
  and a retry re-asks only what it missed.
  """

  @kinds [:search, :details, :editions, :chapters]

  @doc "The outcome id a provider's answer of this kind is recorded under."
  def id(provider_id, kind \\ :search)
  def id(provider_id, :search), do: provider_id
  def id(provider_id, kind) when kind in @kinds, do: "#{provider_id}:#{kind}"

  @doc """
  Splits a recorded id back into the provider and what it was asked.

  The retry chip carries the id, and re-running a search when what failed
  was a details call would report success having fixed nothing.
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

  The reason is kept short and human — enough for the operator to tell a rate
  limit from a bad token from an instance being down, without leaking a whole
  HTTP response into jsonb.
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

  Some of what it was asked reached it and some did not — Audible's regional
  catalogs are the case this exists for: one marketplace rate-limited while
  the others answered used to be indistinguishable from a marketplace with
  nothing in it, which is the one distinction the setting exists to make.

  **Recorded as a failure, and deliberately.** Everything that reads these —
  `Ambry.Inbox.unreached_providers/1`, the retry chip, `failed?/1` — asks one
  question of them: is there something here that a retry could still get? For
  a partial answer there is, so it says `failed` and carries the count of
  what did come back, and the chip words itself off `partial`. A third status
  would have meant teaching every reader a third answer to a question that
  only has two.
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
  # reached: it doesn't implement this kind of call, it is switched off, or it
  # has no credentials. No request was made, so there is nothing to report and
  # nothing a retry could change.
  @unaskable [:unsupported_capability, :provider_disabled, :provider_not_configured]

  # The provider answered, and the answer is that it has no such record. That
  # is "found nothing", which is a count of zero — not a failure.
  @answered [:not_found]

  @doc """
  What to record when a call comes back an error.

  **Not every error is a failure to reach a provider**, and treating them
  alike is what put a permanent red "couldn't be reached, retry" chip on
  items whose retry could never succeed: Audible implements no details call
  at all, and a Hardcover details lookup that 404s is a definite answer. Both
  also kept `Ambry.Inbox.unreached_providers/1` non-empty, which sent the
  matching job round again for as long as it had attempts left.

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
