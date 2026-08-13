defmodule Ambry.Inbox.Draft.Tier do
  @moduledoc """
  How settled one decision is, in the four words the whole form speaks.

  ## Why four and not two

  Settled-versus-waiting answered "can this be imported" and threw away the
  more useful question, which is **did a human ever look at this**. The form
  had two vocabularies for the remaining nuance — per-decision ("settled",
  "needs confirming") and per-level ("confirmed", "trusted", "unsure") — plus
  a Confirm button that, in every state where it was visible, changed nothing
  but its own badge, because everything it set was already set.

  One vocabulary replaces all of it:

    * `:blocked` — nothing proposed a value and none can be chosen; the
      operator has to supply one or the import is refused
    * `:waiting` — the machine couldn't settle it; look here
    * `:unreviewed` — the machine settled it and nobody has looked
    * `:reviewed` — a human has been here

  A freshly matched import is therefore entirely `:unreviewed`, and
  `:reviewed` accumulates as the operator works through it. **`:unreviewed` is
  a legitimate end state**: the goal of an import is no `:waiting` and no
  `:blocked`, never "all reviewed", or every import becomes a chore of
  re-picking values that were already right.

  ## Reviewed is one-way

  It records that a human looked, which is a fact about history — a control
  that took it back to `:unreviewed` would assert something false. What always
  exists instead is a way back to the machine's *value*; taking it leaves the
  decision `:reviewed`, because the operator looked and decided the machine
  was right, which is exactly the distinction the tier buys.

  It also has teeth beyond the rail: `Draft.curated?/1` reads the same flags,
  and a curated draft is re-derived around the operator's answers rather than
  rebuilt when a retrying provider finally comes back.
  """

  alias Ambry.Inbox.Draft.Chapters
  alias Ambry.Inbox.Draft.Credit
  alias Ambry.Inbox.Draft.Destination
  alias Ambry.Inbox.Draft.Field
  alias Ambry.Inbox.Draft.GroupLink
  alias Ambry.Inbox.Draft.PersonDecision
  alias Ambry.Inbox.Draft.Recording
  alias Ambry.Inbox.Draft.SeriesLink
  alias Ambry.Inbox.Draft.Work

  @typedoc "Worst to best, which is also the order `worst/1` ranks them in."
  @type t :: :blocked | :waiting | :unreviewed | :reviewed

  # Best first. `worst/1` takes the last one it finds.
  @order [:reviewed, :unreviewed, :waiting, :blocked]

  @doc """
  The tier of one decision.

  Every decision type already answers `state/1` with the same four words, so
  this is the same shape everywhere: what the machine managed, crossed with
  whether a human has since touched it.
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

  # A level asks two questions and shows them on two cards, so each card gets
  # its own tier and the level itself is the worse of them. Collapsing both
  # into one number made the cards identical, which tells the operator
  # something needs them without saying which.
  def of(%Work{} = work), do: worst([of_evidence(work), of_identity(work)])
  def of(%Recording{} = recording), do: of_evidence(recording)

  # The destination has no `curated` flag of its own — choosing a root is the
  # only way it is ever approved, so approved *is* the operator's answer.
  def of(%Destination{approved: true}), do: :reviewed
  def of(%Destination{}), do: :waiting

  @doc """
  Which provider records describe this thing — the records card's own tier.

  `doubt` is the machine explaining itself, which the doubt banner renders;
  here it is simply the reason the level isn't settled.
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

  # A level that found nothing is settled: there is nothing to choose
  # between, and the seeder approves it. A doubted one is not.
  defp level_state(_approved, :low_confidence), do: :unconfirmed
  defp level_state(true, _doubt), do: :approved
  defp level_state(_unapproved, _doubt), do: :unconfirmed

  defp curated?(%{curated: curated, evidence_curated: evidence}), do: curated or evidence

  defp from(:approved, true), do: :reviewed
  defp from(:approved, _untouched), do: :unreviewed
  defp from(:missing, _curated), do: :blocked
  defp from(_unsettled, _curated), do: :waiting

  @doc """
  The tier a card wears on behalf of its children.

  Worst-first, and `:reviewed` only when *every* child is: a card claiming
  the operator has been through it while one field inside still waits is the
  aggregate lying. Scanning stays honest — look for `:blocked` and `:waiting`,
  then decide whether you care about `:unreviewed`.

  An empty list is `:unreviewed`: "Not in a series" is something the machine
  worked out and nobody has confirmed, not something a human decided.
  """
  def worst([]), do: :unreviewed

  def worst(tiers) when is_list(tiers),
    do: Enum.max_by(tiers, &Enum.find_index(@order, fn tier -> tier == &1 end))

  @doc """
  The tiers of a list of decisions, collapsed to the one its card wears.
  """
  def of_all(decisions), do: decisions |> Enum.map(&of/1) |> worst()

  @doc """
  Whether this tier still wants the operator.

  What the footer counts and what "no amber, no red" means in code.
  """
  def outstanding?(tier), do: tier in [:blocked, :waiting]
end
