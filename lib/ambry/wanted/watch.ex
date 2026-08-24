defmodule Ambry.Wanted.Watch do
  @moduledoc """
  An audiobook the operator is waiting for.

  **Identity is the provider's, never an ASIN.** Most audio editions that have
  ever existed do not have one, and where one exists it differs per regional
  marketplace for the same recording. The ASIN lives in the snapshot as a
  matching key instead.

  Three states:

    * `:upcoming` — waiting. Once `expected_release_date` has passed this is
      *due*: the date arrived, which is not the same as the book existing.
    * `:released` — it exists. Set by the operator, or by an import.
    * `:dismissed` — stop nagging, without pretending it arrived. A watch is
      never deleted on a change of mind, because "did I already decide about
      this?" is otherwise asked twice.
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
  The changeset for the fields the operator edits after the fact. The date is
  editable because publishers move dates and providers lag behind them.
  """
  def edit_changeset(watch, attrs) do
    watch
    |> cast(attrs, [:expected_release_date, :status, :note])
    |> validate_required([:status])
  end

  @doc """
  The changeset for settling a watch against a recording.

  Separate from `edit_changeset/2`, which is the operator's form: `media_id`
  is set by the import that answered the watch, and casting it there would
  invite a crafted parameter.
  """
  def settle_changeset(watch, attrs) do
    watch
    |> cast(attrs, [:status, :media_id])
    |> validate_required([:status])
    |> assoc_constraint(:media)
  end

  @doc """
  Whether the expected date has arrived.

  Deliberately not `released?`: all this knows is that a date passed, and
  whether the recording exists is the operator's or an import's to say.
  """
  def due?(watch, today \\ Date.utc_today())

  def due?(%__MODULE__{status: :upcoming, expected_release_date: %Date{} = date}, today),
    do: Date.compare(date, today) != :gt

  def due?(%__MODULE__{}, _today), do: false
end
