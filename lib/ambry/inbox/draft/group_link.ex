defmodule Ambry.Inbox.Draft.GroupLink do
  @moduledoc """
  The recording's proposed place in a part set: which `RecordingGroup` it
  joins (or creates), and its part number within it.

  The mirror of `SeriesLink`, one level down — a media belongs to a group
  with a part number the way a book belongs to a series with a book number —
  but singular: a media is in at most one group, so the draft holds at most
  one of these. `mode: :link` joins an existing group (Part 2 arriving after
  Part 1 created the set); `mode: :create` mints one, carrying the set-level
  facts (name, optional total) the new group is born with.

  ## The part number never auto-resolves without a source

  Same doctrine as `SeriesLink.number`: "part of this set, position unknown"
  is a question, not an answer. Detection may propose the number; only a
  proposal or the operator supplies it, and the escape hatch is removing the
  link, not importing an unnumbered part.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key false

  embedded_schema do
    field :name, :string

    # What the evidence called it, frozen at seed time — the way back after a
    # rename or an accidental clear (same as `SeriesLink.proposed_name`).
    field :proposed_name, :string

    field :mode, Ecto.Enum, values: [:link, :create], default: :create
    field :recording_group_id, :id

    field :part_number, :integer

    # On `:create`, the total the new group is born with; on `:link` it
    # mirrors the linked group's total for display and is ignored at import.
    field :parts_total, :integer

    field :source, :string
    field :approved, :boolean, default: false

    # Touched by the operator — a number they typed, a set they renamed or
    # pointed elsewhere. Survives re-derivation.
    field :curated, :boolean, default: false

    # Same tombstone as `SeriesLink.removed`: removing a *proposal* is a
    # decision that must survive reseeds and stay reversible. A link the
    # operator added themselves really deletes (the embed goes nil).
    field :removed, :boolean, default: false

    embeds_many :candidates, __MODULE__.Match, on_replace: :delete
  end

  defmodule Match do
    @moduledoc "An existing recording group this proposal could mean."

    use Ecto.Schema

    import Ecto.Changeset

    @primary_key false

    embedded_schema do
      field :recording_group_id, :id
      field :name, :string
      field :parts_total, :integer
    end

    @doc false
    def changeset(match, attrs),
      do: cast(match, attrs, [:recording_group_id, :name, :parts_total])
  end

  @doc false
  def changeset(group_link, attrs) do
    group_link
    |> cast(attrs, [
      :name,
      :proposed_name,
      :mode,
      :recording_group_id,
      :part_number,
      :parts_total,
      :source,
      :approved,
      :curated,
      :removed
    ])
    |> cast_embed(:candidates)
    |> validate_number(:part_number, greater_than_or_equal_to: 1)
    |> validate_number(:parts_total, greater_than_or_equal_to: 1)
    |> validate_part_within_total()
    |> validate_link()
  end

  defp validate_part_within_total(changeset) do
    part = get_field(changeset, :part_number)
    total = get_field(changeset, :parts_total)

    if part && total && part > total do
      add_error(changeset, :part_number, "can't be greater than the total number of parts")
    else
      changeset
    end
  end

  defp validate_link(changeset) do
    if get_field(changeset, :mode) == :link do
      validate_required(changeset, [:recording_group_id])
    else
      changeset
    end
  end

  @doc """
  Whether this set membership still needs a human.

  A membership needs a part number to settle (see the moduledoc), plus the
  group itself: an existing one by id, or a name for the one being created.
  A blank name is storable — clearing the box to retype is the first half of
  renaming — but never resolved.
  """
  def resolved?(%__MODULE__{part_number: nil}), do: false

  def resolved?(%__MODULE__{approved: true, mode: :link, recording_group_id: id}),
    do: not is_nil(id)

  def resolved?(%__MODULE__{approved: true, mode: :create, name: name}) when is_binary(name),
    do: String.trim(name) != ""

  def resolved?(%__MODULE__{}), do: false

  def state(%__MODULE__{} = link) do
    cond do
      resolved?(link) -> :approved
      is_nil(link.part_number) -> :missing
      true -> :unconfirmed
    end
  end
end
