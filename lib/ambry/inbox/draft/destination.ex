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

  ## `chosen` is the whole point of this struct

  A destination holds two values and one fact about them: did a human pick
  these, or did they fall out of a default? Without that fact a seeded
  default is indistinguishable from a decision, and the consequence is not
  theoretical — a draft is written once, at match time, and then only ever
  read. Change what the default *should* be and every already-seeded draft
  keeps the old one forever, because nothing can tell "the operator wanted
  hardlink" from "hardlink is what the default was on Tuesday".

  So `chosen` means the operator picked, and an unchosen destination is
  re-derived from current defaults every time the item is prepared
  (`Inbox.prepare_draft/1`). Defaults follow the latest thinking; decisions
  don't move.

  There is deliberately no separate `approved` flag. It only ever held
  `root_id != nil and policy != nil`, which is `resolved?/1` — a stored copy
  of a derivable fact, free to disagree with the fields it was derived from.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key false

  embedded_schema do
    field :root_id, :id
    field :policy, Ecto.Enum, values: [:hardlink, :symlink, :copy, :move]

    # Whether a human picked the two above. False means they are a default
    # and may be re-derived; see the moduledoc.
    field :chosen, :boolean, default: false

    # Filled in at render time from the registry rather than stored: roots are
    # configuration and can change between seeding a draft and approving it.
    field :roots, {:array, :map}, virtual: true, default: []
  end

  @doc false
  def changeset(destination, attrs) do
    cast(destination, attrs, [:root_id, :policy, :chosen])
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
  Marks the destination as the operator's own, so defaults stop moving it.
  """
  def choose(%__MODULE__{} = destination, changes),
    do: struct!(%{destination | chosen: true}, changes)

  def state(%__MODULE__{} = destination) do
    cond do
      resolved?(destination) -> :approved
      destination.roots == [] -> :missing
      true -> :ambiguous
    end
  end
end
