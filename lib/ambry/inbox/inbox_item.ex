defmodule Ambry.Inbox.InboxItem do
  @moduledoc """
  One candidate recording waiting to be curated into the library.

  An item references files where they landed — nothing is copied, linked, or
  organized until it's imported. `path` is the item's identity (the release
  folder, or a loose file), which is what makes rescans idempotent and keeps
  ignored items ignored.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Ambry.Inbox.Draft
  alias Ambry.Inbox.ReleaseName
  alias Ambry.Library.Source
  alias Ambry.Media.Media

  @statuses [:pending, :ignored, :imported]

  schema "inbox_items" do
    belongs_to :media, Media

    # Where this was found, which seeds the placement policy import brings
    # its files into a library root with. Nullable: items from an ad-hoc
    # scan have no source to speak for them, so the operator picks the
    # policy at approval.
    belongs_to :source, Source

    field :path, :string
    field :files, {:array, :string}, default: []
    field :status, Ecto.Enum, values: @statuses, default: :pending
    field :probe, :map
    field :tags, :map
    field :matches, :map
    field :issue, :string

    # Derived from the draft, denormalized so the queue filters and counts in
    # SQL. `put_draft/2` is its only writer.
    field :ready, :boolean, default: false

    embeds_one :draft, Draft, on_replace: :update

    timestamps(type: :utc_datetime)
  end

  def statuses, do: @statuses

  @doc false
  def changeset(inbox_item, attrs) do
    inbox_item
    |> cast(attrs, [
      :path,
      :files,
      :status,
      :probe,
      :tags,
      :matches,
      :issue,
      :media_id,
      :source_id
    ])
    |> validate_required([:path, :status])
    |> unique_constraint(:path)
  end

  @doc """
  Stages a draft, keeping the denormalized `ready` flag in step.

  Readiness is *defined* by `Draft.resolved?/1` and merely *stored* here.
  Routing every draft write through one function is what stops the column
  drifting away from the function — there is no second place that may set it.
  """
  def put_draft(inbox_item, attrs) do
    changeset =
      inbox_item
      |> cast(%{draft: attrs}, [])
      |> cast_embed(:draft)

    put_change(changeset, :ready, Draft.resolved?(fetch_field!(changeset, :draft)))
  end

  @doc """
  A short label for the item: the folder or file name, which is usually the
  release name and the most recognizable thing about it.

  The exception is a name that states nothing but a position in a set: an item split out of "The Way of Kings/1 of 5" is called "1 of 5",
  which in a queue of five siblings and 300 other releases says nothing at
  all. Those carry the folder they are a part of.
  """
  def name(%__MODULE__{path: path}) do
    base = Path.basename(path)

    if ReleaseName.part_folder?(base),
      do: Path.join(Path.basename(Path.dirname(path)), base),
      else: base
  end
end
