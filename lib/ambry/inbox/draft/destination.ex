defmodule Ambry.Inbox.Draft.Destination do
  @moduledoc """
  Where this import's files are going, and what will be done to them.

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

  ## Policy belongs to the input; feasibility belongs to the pair

  `hardlink | copy | move` describes what you want done with the *source* —
  preserve it for seeding, or clear it out — so it's a property of where the
  files came from. Whether a hardlink is actually possible depends on the
  input and output being on one filesystem, which is a fact about the
  *pairing* and can only be checked once both ends are known.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key false

  embedded_schema do
    # :external adopts the files where they lie and is settled by definition —
    # there is no destination to choose.
    field :custody, Ecto.Enum, values: [:managed, :external], default: :external
    field :root_id, :id
    field :policy, Ecto.Enum, values: [:hardlink, :copy, :move]
    field :approved, :boolean, default: false

    # Filled in at render time from the registry rather than stored: roots are
    # configuration and can change between seeding a draft and approving it.
    field :roots, {:array, :map}, virtual: true, default: []
  end

  @doc false
  def changeset(destination, attrs) do
    destination
    |> cast(attrs, [:custody, :root_id, :policy, :approved])
    |> validate_managed_has_root()
  end

  # An approved managed import with no root is not a decision — it's one that
  # would fail at the moment of placement, which is precisely what the
  # invariant exists to prevent.
  defp validate_managed_has_root(changeset) do
    approved? = get_field(changeset, :approved)
    managed? = get_field(changeset, :custody) == :managed

    if approved? and managed? and is_nil(get_field(changeset, :root_id)) do
      add_error(changeset, :root_id, "needs a library root to import into")
    else
      changeset
    end
  end

  @doc """
  Whether the destination still needs a human.

  External custody is settled by construction: the files stay exactly where
  they are, so there is nothing to decide.
  """
  def resolved?(%__MODULE__{custody: :external}), do: true
  def resolved?(%__MODULE__{approved: true, root_id: id}), do: not is_nil(id)
  def resolved?(%__MODULE__{}), do: false

  def state(%__MODULE__{} = destination) do
    cond do
      resolved?(destination) -> :approved
      destination.roots == [] -> :missing
      true -> :ambiguous
    end
  end
end
