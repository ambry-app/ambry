defmodule Ambry.Inbox.Draft.Destination do
  @moduledoc """
  Where this import's files are going, and what will be done to them.

  Every import places into a library root, so a destination is two choices:
  **which root**, and **which policy** (hardlink, symlink, copy or move)
  brings the files in.

  A watched folder is an input and a library root is an output, and any input
  may feed any output, so the destination is decided per import rather than
  configured as a fixed pairing. Which makes it a decision like any other:
  auto-resolved when there is exactly one root, outstanding when there are
  several.

  The policy describes what happens to the *source*, so its default comes from
  where the files came from; whether a hardlink is actually possible depends
  on both ends being on one filesystem, which is a fact about the pairing.

  ## The `chosen` flags are the whole point of this struct

  Without them a seeded default is indistinguishable from a decision, and a
  draft is written once at match time and then only read: change what the
  default should be and every already-seeded draft would keep the previous one
  forever.

  So an unchosen half is re-derived from current defaults every time the item
  is prepared (`Inbox.prepare_draft/1`). Defaults follow the latest thinking;
  decisions don't move. Clearing a picker back to its blank option un-picks
  it, which is the only way to change one's mind about having decided at all.

  The two flags are separate because the two questions are: picking a root
  re-derives an unchosen policy rather than freezing whatever the previous
  root implied.

  There is deliberately no `approved` flag: it would only ever hold what
  `resolved?/1` derives.
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

  Both halves present is the whole test, however they got there: an import
  missing either would fail at the moment of placement.
  """
  def resolved?(%__MODULE__{root_id: root_id, policy: policy}),
    do: not is_nil(root_id) and not is_nil(policy)

  @doc """
  Picks a root, or hands the choice back to the default when given `nil`.

  Blank is how an operator un-decides; recording it as "chose nothing" would
  leave the import unresolvable with no way back.
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
