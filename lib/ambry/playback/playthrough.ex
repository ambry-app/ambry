defmodule Ambry.Playback.Playthrough do
  @moduledoc """
  Represents a user's journey through a book, from start to finish or abandon.

  A playthrough tracks the complete lifecycle of listening to a media item,
  including all play, pause, seek, and rate change events. Multiple playthroughs
  can exist for the same user/media pair (e.g., re-listens).

  ## Status Lifecycle

       ┌────────────────┐
       │ No playthrough │
       └───────┬────────┘
               ▼
             Start
               │
               ▼
        ┌─────────────┐
   ┌───►│ In progress ├──────┐
   │    └──────┬──────┘      │
   │           ▼             ▼
   │        Abandon        Finish
   │           │             │
   │           ▼             ▼
   │     ┌───────────┐  ┌──────────┐
   │     │ Abandoned │  │ Finished │
   │     └─────┬─────┘  └────┬─────┘
   │           ▼             │
   └────────Resume◄──────────┘

  - `in_progress`: Currently listening (only one active per user/media)
  - `finished`: Completed (auto-detected near end, or explicit)
  - `abandoned`: Explicitly abandoned by user
  - Both `finished` and `abandoned` can be resumed to `in_progress`

  ## Soft Deletes

  Playthroughs can be soft-deleted by setting `deleted_at`. This is used when
  a user wants to completely remove a playthrough (e.g., accidentally opened
  a book they didn't intend to listen to). Soft deletes enable proper sync
  across devices - the deletion propagates to other clients.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Ambry.Accounts.User
  alias Ambry.Media.Media
  alias Ambry.Playback.PlaybackEvent

  @primary_key {:id, :binary_id, autogenerate: false}
  @foreign_key_type :binary_id

  schema "playthroughs" do
    belongs_to :media, Media, type: :id
    belongs_to :user, User, type: :id

    has_many :events, PlaybackEvent

    field :status, Ecto.Enum,
      values: [:in_progress, :finished, :abandoned],
      default: :in_progress

    field :started_at, :utc_datetime
    field :finished_at, :utc_datetime
    field :abandoned_at, :utc_datetime
    field :deleted_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  @doc """
  Creates a changeset for a new playthrough.

  Requires a client-generated UUID as the id.
  """
  def changeset(playthrough, attrs) do
    playthrough
    |> cast(attrs, [
      :id,
      :media_id,
      :user_id,
      :status,
      :started_at,
      :finished_at,
      :abandoned_at,
      :deleted_at
    ])
    |> validate_required([:id, :media_id, :user_id, :status, :started_at])
    |> validate_status_timestamps()
    |> unique_constraint([:user_id, :media_id, :started_at],
      name: :playthroughs_user_id_media_id_started_at_index
    )
  end

  @doc """
  Creates a changeset for finishing a playthrough.
  """
  def finish_changeset(playthrough) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    playthrough
    |> change(status: :finished, finished_at: now)
  end

  @doc """
  Creates a changeset for abandoning a playthrough.
  """
  def abandon_changeset(playthrough) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    playthrough
    |> change(status: :abandoned, abandoned_at: now)
  end

  @doc """
  Creates a changeset for soft-deleting a playthrough.
  """
  def delete_changeset(playthrough) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    playthrough
    |> change(deleted_at: now)
  end

  @doc """
  Creates a changeset for resuming a finished or abandoned playthrough.

  Reverts status to in_progress and clears finished_at/abandoned_at.
  """
  def resume_changeset(playthrough) do
    playthrough
    |> change(status: :in_progress, finished_at: nil, abandoned_at: nil)
  end

  defp validate_status_timestamps(changeset) do
    status = get_field(changeset, :status)

    case status do
      :finished ->
        validate_required(changeset, [:finished_at])

      :abandoned ->
        validate_required(changeset, [:abandoned_at])

      _ ->
        changeset
    end
  end
end
