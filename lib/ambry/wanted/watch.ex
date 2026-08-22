defmodule Ambry.Wanted.Watch do
  @moduledoc """
  An audiobook the operator is waiting for.

  ## Identity is the provider's, not Amazon's

  A watch is keyed on `provider` + `provider_id`, never on ASIN. Most audio
  editions that have ever existed do not have one — the 1984 Books on Tape
  recordings of *Neuromancer* predate Amazon — and where an ASIN does exist it
  differs per Audible marketplace for the same recording. The ASIN lives in
  the snapshot as a matching key instead, alongside title, narrators and
  publisher.

  ## Three states, and what each one means

    * `:upcoming` — waiting. If `expected_release_date` has passed this is
      *due*: the date arrived, which is not the same as the book existing.
      Being due is the whole point of the feature; it is what nags.
    * `:released` — it exists. Set by the operator, or when an import
      satisfies it.
    * `:dismissed` — stop nagging, without pretending it arrived. A watch is
      never deleted on a change of mind, because "did I already decide about
      this?" is a question the operator will otherwise ask twice.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Ambry.Media.Media
  alias Ambry.Wanted.Edition

  @statuses [:upcoming, :released, :dismissed]

  schema "watches" do
    belongs_to :media, Media

    field :provider, :string
    field :provider_id, :string

    embeds_one :edition, Edition, on_replace: :update

    field :expected_release_date, :date
    field :status, Ecto.Enum, values: @statuses, default: :upcoming
    field :note, :string

    timestamps(type: :utc_datetime)
  end

  @doc "The states a watch can be in."
  def statuses, do: @statuses

  @doc false
  def changeset(watch, attrs) do
    watch
    |> cast(attrs, [:provider, :provider_id, :expected_release_date, :status, :note, :media_id])
    |> cast_embed(:edition, required: true)
    |> validate_required([:provider, :provider_id, :status])
    |> unique_constraint([:provider, :provider_id],
      message: "is already being watched"
    )
  end

  @doc """
  The changeset for the fields the operator edits after the fact.

  The date is editable because publishers move dates and providers lag behind
  them; the operator usually knows before the provider does.
  """
  def edit_changeset(watch, attrs) do
    watch
    |> cast(attrs, [:expected_release_date, :status, :note])
    |> validate_required([:status])
  end

  @doc """
  Whether the expected date has arrived.

  Deliberately not called `released?`. All this knows is that a date passed —
  whether the recording exists is a question only the operator or an import
  can answer, and conflating the two is how a list starts lying.
  """
  def due?(watch, today \\ Date.utc_today())

  def due?(%__MODULE__{status: :upcoming, expected_release_date: %Date{} = date}, today),
    do: Date.compare(date, today) != :gt

  def due?(%__MODULE__{}, _today), do: false
end
