defmodule Ambry.Inbox.Draft.Replacement do
  @moduledoc """
  Whether these files are a new audiobook, or better files for one the
  library already has.

  ## Why it is a decision and not a tool

  An operator upgrading a legacy recording to direct play does it one
  audiobook at a time, through the form they already use: no batch, no flag
  day, and the transcode pipeline retires when the last legacy recording
  does. That only works if replacing is an *answer on the import form* — the
  same shape as "is this a book you already have", one level up.

  ## It collapses the rest of the form

  Choosing a recording settles everything below it. The audiobook already has
  its book, its credits, its chapters and its metadata; none of them are in
  question, and re-deciding them would be an invitation to overwrite curation
  with whatever a provider says today. What remains is where the new files go
  — `Ambry.Inbox.Draft.Destination`, exactly as for any other import.

  ## Proposed from the path evidence, confirmed by a human

  `Ambry.Media.imported_from/1` says which recording a file was imported
  into. Discovery used to read the same data to *hide* the file; here it
  pre-fills this decision instead. A proposal arrives unapproved, because
  "the files this was made from turned up again" and "these files should
  replace it" are not the same statement — the first is evidence, the second
  is the operator's.

  With no evidence the answer is settled as `:new` and nothing is asked: an
  ordinary import must not grow a question it has to answer three hundred
  times. `curated` is what keeps a human's answer from being re-proposed
  over on the next prepare, the same flag `Work` draws for the same reason.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key false

  embedded_schema do
    field :mode, Ecto.Enum, values: [:new, :replace], default: :new
    field :media_id, :id
    field :approved, :boolean, default: false

    # Whether a human settled this, as opposed to the seeder settling it
    # because no recording claims these files.
    field :curated, :boolean, default: false
  end

  @doc false
  def changeset(replacement, attrs) do
    replacement
    |> cast(attrs, [:mode, :media_id, :approved, :curated])
    |> validate_replacement()
  end

  defp validate_replacement(changeset) do
    if get_field(changeset, :mode) == :replace do
      validate_required(changeset, [:media_id])
    else
      changeset
    end
  end

  @doc """
  Whether this import is replacing an existing audiobook's files.

  **Answered, not proposed.** Everything that keys on this hides the rest of
  the form, and a form collapsed on the strength of a guess is one that
  decided for the operator: until they confirm, the book and audiobook
  decisions below are still theirs to make and still outstanding.

  Absent on drafts that predate the decision, which are ordinary imports.
  """
  def replacing?(nil), do: false

  def replacing?(%__MODULE__{mode: :replace, media_id: id, approved: true}), do: is_integer(id)

  def replacing?(%__MODULE__{}), do: false

  @doc """
  Whether the decision still needs a human.
  """
  def resolved?(%__MODULE__{approved: false}), do: false
  def resolved?(%__MODULE__{mode: :replace, media_id: nil}), do: false
  def resolved?(%__MODULE__{}), do: true

  def state(%__MODULE__{} = replacement) do
    if resolved?(replacement), do: :approved, else: :unconfirmed
  end

  @doc """
  Settles that these files replace an audiobook already in the library.
  """
  def replace(%__MODULE__{} = replacement, media_id) when is_integer(media_id),
    do: %{replacement | mode: :replace, media_id: media_id, approved: true, curated: true}

  @doc """
  Settles that this is an audiobook the library doesn't have yet.

  The proposal is kept rather than cleared: a declined suggestion still has
  to be on the form, or "no" would be the one decision on it with no way
  back.
  """
  def new(%__MODULE__{} = replacement),
    do: %{replacement | mode: :new, approved: true, curated: true}
end
