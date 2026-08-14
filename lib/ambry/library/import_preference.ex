defmodule Ambry.Library.ImportPreference do
  @moduledoc """
  What the last import from one source into one root did.

  ## Why this is a memory and not a setting

  Which of `hardlink | symlink | copy | move` an import uses is a property
  of the **pairing**, not of either end. A hardlink is only possible when
  the two paths share a filesystem, so the same downloads folder feeding two
  roots on two NAS boxes genuinely wants two different answers — which a
  policy stored on the source cannot express, and which the operator would
  have to correct by hand on every import into the second root.

  It is also not stable enough to be configuration. The choice is a real
  per-import decision — normally hardlink from downloads, but this one
  release isn't seeding and the folder should be left clean — and a settings
  field that is overridden half the time is not a setting, it is a default
  wearing configuration's costume.

  So nothing is configured. The pairing remembers what it last did, and the
  next import proposes that. `last_used_at` doubles as the *root* default:
  the root a source most recently imported into is the one it proposes next.

  ## What a memory is not allowed to do

  Only propose. A remembered `:hardlink` for a pairing that has since moved
  to another filesystem is still refused at the point of placement — see
  `Ambry.Library.Placement` — because a memory is evidence about what the
  operator wanted, never a claim about what the disk can do.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Ambry.Library.Root
  alias Ambry.Library.Source

  schema "import_preferences" do
    belongs_to :source, Source
    belongs_to :library_root, Root

    field :policy, Ecto.Enum, values: [:hardlink, :symlink, :copy, :move]
    field :last_used_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(preference, attrs) do
    preference
    |> cast(attrs, [:source_id, :library_root_id, :policy, :last_used_at])
    |> validate_required([:source_id, :library_root_id, :policy, :last_used_at])
    |> foreign_key_constraint(:source_id)
    |> foreign_key_constraint(:library_root_id)
    |> unique_constraint([:source_id, :library_root_id])
  end
end
