defmodule Ambry.Inbox.Draft.Tier do
  @moduledoc """
  How settled one decision is, in the words the whole form speaks.

    * `:blocked` — nothing proposed a value and none can be chosen; the
      operator has to supply one or the import is refused
    * `:waiting` — the machine couldn't settle it; look here
    * `:uncatalogued` — no provider lists this at all
    * `:unreviewed` — the machine settled it and nobody has looked
    * `:reviewed` — a human has been here

  A freshly matched import is entirely `:unreviewed`, and that is a
  legitimate end state: the goal is no `:waiting` and no `:blocked`, never
  "all reviewed".

  `:reviewed` is one-way — it records that a human looked. Reverting to the
  machine's *value* is always offered, and leaves the decision `:reviewed`.
  `Draft.curated?/1` reads the same flags, so a curated draft is re-derived
  around the operator's answers rather than rebuilt.
  """

  alias Ambry.Inbox.Draft.Chapters
  alias Ambry.Inbox.Draft.Credit
  alias Ambry.Inbox.Draft.Destination
  alias Ambry.Inbox.Draft.Field
  alias Ambry.Inbox.Draft.GroupLink
  alias Ambry.Inbox.Draft.PersonDecision
  alias Ambry.Inbox.Draft.Recording
  alias Ambry.Inbox.Draft.Replacement
  alias Ambry.Inbox.Draft.SeriesLink
  alias Ambry.Inbox.Draft.Work

  @typedoc "Worst to best, which is also the order `worst/1` ranks them in."
  @type t :: :blocked | :waiting | :uncatalogued | :unreviewed | :reviewed

  # Best first. `:uncatalogued` sits below `:unreviewed` and above
  # `:waiting`: worth a look, but not a question the operator can answer by
  # choosing something.
  @order [:reviewed, :unreviewed, :uncatalogued, :waiting, :blocked]

  @doc """
  The tier of one decision: what the machine managed, crossed with whether a
  human has since touched it.
  """
  def of(%Field{} = field), do: from(Field.state(field), field.curated)
  def of(%Credit{} = credit), do: from(Credit.state(credit), credit.curated)
  def of(%SeriesLink{} = link), do: from(SeriesLink.state(link), link.curated)
  def of(%GroupLink{} = link), do: from(GroupLink.state(link), link.curated)
  def of(%PersonDecision{} = person), do: from(PersonDecision.state(person), curated?(person))

  # Chapters answer `resolved?/1` rather than `state/1`: a list of markers
  # read off the files is never *missing*, only unapproved.
  def of(%Chapters{} = chapters),
    do:
      from(if(Chapters.resolved?(chapters), do: :approved, else: :unconfirmed), chapters.curated)

  # A level asks two questions on two cards, so each card gets its own tier
  # and the level is the worse of them.
  def of(%Work{} = work), do: worst([of_evidence(work), of_identity(work)])
  def of(%Recording{} = recording), do: of_evidence(recording)

  # Settled whether the operator picked or the single-root default did: that
  # resolution is meant to be indistinguishable from an answer.
  def of(%Destination{} = destination),
    do: if(Destination.resolved?(destination), do: :reviewed, else: :waiting)

  def of(%Replacement{} = replacement),
    do: from(Replacement.state(replacement), replacement.curated)

  @doc """
  Which provider records describe this thing — the records card's own tier.
  """
  def of_evidence(%Work{} = work),
    do: from(level_state(work.approved, work.doubt), work.evidence_curated)

  def of_evidence(%Recording{} = recording),
    do: from(level_state(recording.approved, recording.doubt), recording.evidence_curated)

  @doc """
  Whether this is a book the library already has — the identity card's tier.

  Only the work level asks it: a recording is always created, never linked.
  """
  def of_identity(%Work{} = work),
    do: from(if(work.approved, do: :approved, else: :unconfirmed), work.curated)

  # A level that found nothing is settled — the seeder approves it so a
  # release no catalogue lists can still be imported from its own tags — but
  # it is not *matched*, so it gets its own word. Worth surfacing: with
  # several providers asked, finding nothing usually means a polluted query.
  defp level_state(_approved, :nothing_found), do: :uncatalogued
  defp level_state(_approved, :low_confidence), do: :unconfirmed
  defp level_state(true, _doubt), do: :approved
  defp level_state(_unapproved, _doubt), do: :unconfirmed

  defp curated?(%{curated: curated, evidence_curated: evidence}), do: curated or evidence

  defp from(:approved, true), do: :reviewed
  defp from(:approved, _untouched), do: :unreviewed

  # A human who has been through an uncatalogued level has answered the only
  # question it poses, so it stops flagging itself.
  defp from(:uncatalogued, true), do: :reviewed
  defp from(:uncatalogued, _untouched), do: :uncatalogued
  defp from(:missing, _curated), do: :blocked

  # `books_series.book_number` is required, so an unnumbered membership is as
  # blocked as a field nobody proposed a value for.
  defp from(:unnumbered, _curated), do: :blocked
  defp from(_unsettled, _curated), do: :waiting

  @doc """
  The tier a card wears on behalf of its children: the worst of them, so
  `:reviewed` only when every child is.

  An empty list is `:unreviewed` — "Not in a series" is something the machine
  worked out, not something a human decided.
  """
  def worst([]), do: :unreviewed

  def worst(tiers) when is_list(tiers),
    do: Enum.max_by(tiers, &Enum.find_index(@order, fn tier -> tier == &1 end))

  @doc """
  The tiers of a list of decisions, collapsed to the one its card wears.
  """
  def of_all(decisions), do: decisions |> Enum.map(&of/1) |> worst()

  @doc """
  Whether this tier still wants the operator; what the footer counts.
  """
  def outstanding?(tier), do: tier in [:blocked, :waiting, :uncatalogued]
end
