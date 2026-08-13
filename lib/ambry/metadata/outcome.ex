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
