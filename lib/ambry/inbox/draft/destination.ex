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
  default comes from where the files came from (`Source.import_policy`). An
  item with no source has no default and the policy is a real outstanding
  decision. Whether a hardlink is actually possible depends on the input and
  output being on one filesystem, which is a fact about the *pairing* and can
  only be checked once both ends are known.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key false

  embedded_schema do
    field :root_id, :id
    field :policy, Ecto.Enum, values: [:hardlink, :symlink, :copy, :move]
    field :approved, :boolean, default: false

    # Filled in at render time from the registry rather than stored: roots are
    # configuration and can change between seeding a draft and approving it.
    field :roots, {:array, :map}, virtual: true, default: []
  end

  @doc false
  def changeset(destination, attrs) do
    destination
    |> cast(attrs, [:root_id, :policy, :approved])
    |> validate_approved_is_placeable()
  end

  # An approved import with no root or no policy is not a decision — it's one
  # that would fail at the moment of placement, which is precisely what the
  # invariant exists to prevent.
  defp validate_approved_is_placeable(changeset) do
    if get_field(changeset, :approved) do
      changeset
      |> validate_present(:root_id, "needs a library root to import into")
      |> validate_present(:policy, "needs a placement policy")
    else
      changeset
    end
  end

  defp validate_present(changeset, field, message) do
    if is_nil(get_field(changeset, field)),
      do: add_error(changeset, field, message),
      else: changeset
  end

  @doc """
  Whether the destination still needs a human.
  """
  def resolved?(%__MODULE__{approved: true, root_id: root_id, policy: policy}),
    do: not is_nil(root_id) and not is_nil(policy)

  def resolved?(%__MODULE__{}), do: false

  def state(%__MODULE__{} = destination) do
    cond do
      resolved?(destination) -> :approved
      destination.roots == [] -> :missing
      true -> :ambiguous
    end
  end
end
