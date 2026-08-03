defmodule Ambry.Inbox.InboxItem do
  @moduledoc """
  One candidate recording waiting to be curated into the library.

  An item references files where they landed — nothing is copied, linked, or
  organized until it's approved. `path` is the item's identity (the release
  folder, or a loose file), which is what makes rescans idempotent and keeps
  dismissed items dismissed.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Ambry.Media.Media

  @statuses [:pending, :dismissed, :approved]

  schema "inbox_items" do
    belongs_to :media, Media

    field :path, :string
    field :files, {:array, :string}, default: []
    field :status, Ecto.Enum, values: @statuses, default: :pending
    field :probe, :map
    field :tags, :map
    field :issue, :string

    timestamps(type: :utc_datetime)
  end

  def statuses, do: @statuses

  @doc false
  def changeset(inbox_item, attrs) do
    inbox_item
    |> cast(attrs, [:path, :files, :status, :probe, :tags, :issue, :media_id])
    |> validate_required([:path, :status])
    |> unique_constraint(:path)
  end

  @doc """
  A short label for the item: the folder or file name, which is usually the
  release name and the most recognizable thing about it.
  """
  def name(%__MODULE__{path: path}), do: Path.basename(path)
end
