defmodule Ambry.Inbox.Draft.Destination do
  @moduledoc """
  Where this import's files are going, and what will be done to them.

  Every import places into a library root — there is no other place Ambry
  serves from — so a destination is two choices: **which root**, and **which
  policy** (hardlink, symlink, copy or move) brings the files in.

  ## Inputs and outputs are independent

  A watched folder is an *input*; a library root is an *output*. Any input may
  feed any output, so the destination is decided per import rather than
  configured as a fixed pairing on the input — a downloads folder that can
  only ever reach one root is a constraint nobody asked for, and adding a
  second root shouldn't retroactively make every existing input ambiguous.

  Which makes this a decision like any other: **auto-resolved when there's
  exactly one root** (the overwhelmingly common case, and one the operator
  should never be asked about), and outstanding when there are several. A
  location may still name a *preferred* root, which seeds the choice without
  binding it.

  ## Policy is seeded by the input; feasibility belongs to the pair

  `hardlink | symlink | copy | move` describes what happens to the *source* —
  preserve it for seeding, reference it in place, or clear it out — so its
  default comes from where the files came from (`Source.import_policy`).
  Whether a hardlink is actually *possible* depends on the input and output
  being on one filesystem, which is a fact about the **pairing** and can only
  be checked once both ends are known.

  ## The `chosen` flags are the whole point of this struct

  A destination holds two values and one fact about each: did a human pick
  this, or did it fall out of a default? Without that fact a seeded default
  is indistinguishable from a decision, and the consequence is not
  theoretical — a draft is written once, at match time, and then only ever
  read. Change what the default *should* be and every already-seeded draft
  keeps the old one forever, because nothing can tell "the operator wanted
  hardlink" from "hardlink is what the default was on Tuesday".

  So an unchosen half is re-derived from current defaults every time the
  item is prepared (`Inbox.prepare_draft/1`). Defaults follow the latest
  thinking; decisions don't move. Clearing a picker back to its blank option
  un-picks it and hands it back to the default, which is the only way to
  change one's mind about having decided at all.

  The two flags are separate because the two questions are. The policy is a
  fact about the *pairing*, so picking a root re-derives an unchosen policy
  rather than freezing whatever the previous root implied — with one flag,
  answering "which root" would silently also answer "how", using the old
  root's answer.

  There is deliberately no `approved` flag. It only ever held `root_id !=
  nil and policy != nil`, which is `resolved?/1` — a stored copy of a
  derivable fact, free to disagree with the fields it was derived from.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key false

  embedded_schema do
    field :root_id, :id
    field :policy, Ecto.Enum, values: [:hardlink, :symlink, :copy, :move]

    # Whether a human picked each of the two above. False means it is a
    # default and may be re-derived; see the moduledoc.
    field :root_chosen, :boolean, default: false
    field :policy_chosen, :boolean, default: false

    # Filled in at render time from the registry rather than stored: roots are
    # configuration and can change between seeding a draft and approving it.
    field :roots, {:array, :map}, virtual: true, default: []
  end

  @doc false
  def changeset(destination, attrs) do
    cast(destination, attrs, [:root_id, :policy, :root_chosen, :policy_chosen])
  end

  @doc """
  Whether the destination still needs a human.

  Both halves present is the whole test, however they got there. An import
  that knows its root and its policy will place; one missing either would
  fail at the moment of placement, which is exactly what asking is for.
  """
  def resolved?(%__MODULE__{root_id: root_id, policy: policy}),
    do: not is_nil(root_id) and not is_nil(policy)

  @doc """
  Picks a root, or hands the choice back to the default when given `nil`.

  Blank is how an operator un-decides. Recording it as "chose nothing" would
  leave the import permanently unresolvable with no way back short of
  rebuilding the draft.
  """
  def choose_root(%__MODULE__{} = destination, root_id),
    do: %{destination | root_id: root_id, root_chosen: not is_nil(root_id)}

  @doc """
  Picks a policy, or hands the choice back to the default when given `nil`.
  """
  def choose_policy(%__MODULE__{} = destination, policy),
    do: %{destination | policy: policy, policy_chosen: not is_nil(policy)}

  def state(%__MODULE__{} = destination) do
    cond do
      resolved?(destination) -> :approved
      destination.roots == [] -> :missing
      true -> :ambiguous
    end
  end
end
