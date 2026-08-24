defmodule Ambry.Library.ImportPreference do
  @moduledoc """
  What the last import from one source into one root did.

  **A memory, not a setting.** Which of `hardlink | symlink | copy | move` an
  import uses is a property of the **pairing**: a hardlink is only possible
  where the two paths share a filesystem, so one downloads folder feeding two
  roots on two volumes genuinely wants two answers, which a policy stored on
  the source cannot express.

  It is also not stable enough to be configuration. The choice is a real
  per-import decision, and a settings field overridden half the time is a
  default wearing configuration's costume.

  So nothing is configured: the pairing remembers what it last did and the
  next import proposes that. `last_used_at` doubles as the *root* default.

  **A memory only proposes.** A remembered `:hardlink` for a pairing that has
  since moved to another filesystem is still refused at placement, because a
  memory is evidence about what the operator wanted and never a claim about
  what the disk can do.

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
