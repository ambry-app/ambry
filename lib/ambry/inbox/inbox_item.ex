defmodule Ambry.Inbox.InboxItem do
  @moduledoc """
  One candidate recording waiting to be curated into the library.

  An item references files where they landed — nothing is copied, linked, or
  organized until it's imported. `path` is the item's identity (the release
  folder, or a loose file), which is what makes rescans idempotent and keeps
  ignored items ignored.

  `path` and `files` are stored relative to the item's source, so a source
  whose mount point changes is a one-row edit and every queued item — and
  the operator decisions staged on it — survives the move. Resolve through
  `disk_path/1` and `disk_files/1`, never by joining the columns against
  anything directly.

  Every item has a source. There is no other way in, which is what makes
  the relative form an invariant rather than a convention.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Ambry.Inbox.Draft
  alias Ambry.Inbox.Draft.Field
  alias Ambry.Inbox.ReleaseName
  alias Ambry.Library
  alias Ambry.Library.Source
  alias Ambry.Media.Media
  alias Ambry.Repo

  @statuses [:pending, :ignored, :imported]

  schema "inbox_items" do
    belongs_to :media, Media

    # The watched folder this was found in, and the base its `path` and
    # `files` are relative to.
    belongs_to :source, Source

    field :path, :string
    field :files, {:array, :string}, default: []
    field :status, Ecto.Enum, values: @statuses, default: :pending
    field :probe, :map
    field :tags, :map
    field :matches, :map
    field :issue, :string

    # Derived from the draft, denormalized so the queue filters and counts in
    # SQL. `put_draft/2` is their only writer.
    field :ready, :boolean, default: false

    # What the draft says this item is, flattened for the queue's search. The
    # `update_inbox_tsvector` trigger turns this and `path` into
    # `search_vector`; nothing reads this column directly.
    # `search_vector` itself is not declared: nothing in Elixir reads a
    # tsvector, the trigger is its only writer, and `Ambry.Search.Record`
    # leaves its own out for the same reason.
    field :search_text, :string

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
    |> validate_required([:path, :status, :source_id])
    |> foreign_key_constraint(:source_id)
    |> unique_constraint(:path)
  end

  @doc """
  Stages a draft, keeping the denormalized `ready` flag in step.

  Readiness is *defined* by `Draft.resolved?/1` and merely *stored* here, and
  the same goes for `search_text`. Routing every draft write through one
  function is what stops either column drifting away from the draft — there
  is no second place that may set them.

  `search_text` is built here rather than in the trigger on purpose. The
  draft is a deep embedded structure — fields wrapping values, credits
  referencing people by key — and SQL reaching into that JSON would be a
  second copy of its shape, going stale the first time the shape changed.
  """
  def put_draft(inbox_item, attrs) do
    changeset =
      inbox_item
      |> cast(%{draft: attrs}, [])
      |> cast_embed(:draft)

    draft = fetch_field!(changeset, :draft)

    changeset
    |> put_change(:ready, Draft.resolved?(draft))
    |> put_change(:search_text, search_text(draft))
  end

  @doc """
  What a draft is findable by, beyond the path it was found at.

  The point of the whole column: an item whose folder is
  `01 Angels and Demons.m4b` is findable by "Dan Brown", which no amount of
  matching on the path can do.

  Titles, credited names and series only — the things somebody would type
  looking for this item. Not dates, not publishers, not the file's own tags:
  a search box that matches everything matches nothing.
  """
  def search_text(nil), do: nil

  def search_text(%Draft{} = draft) do
    work = draft.work
    recording = draft.recording

    [
      work && Field.value(work.title),
      recording && Field.value(recording.title),
      credited(work && work.authors),
      credited(recording && recording.narrators),
      Enum.map(draft.people || [], &Field.value(&1.name)),
      Enum.map((work && work.series) || [], & &1.name)
    ]
    |> List.flatten()
    |> Enum.reject(&(is_nil(&1) or &1 == ""))
    |> Enum.uniq()
    |> case do
      [] -> nil
      parts -> Enum.join(parts, " ")
    end
  end

  defp credited(nil), do: []
  defp credited(credits), do: Enum.map(credits, & &1.name)

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

  @doc """
  The item's absolute path on disk.
  """
  def disk_path(%__MODULE__{path: path} = item), do: resolve!(item, path)

  @doc """
  The item's files as absolute disk paths, in discovery order.
  """
  def disk_files(%__MODULE__{files: files} = item), do: Enum.map(files, &resolve!(item, &1))

  # Raising is deliberate: these paths get probed and placed, and a path that
  # can't resolve must never quietly become a relative one.
  defp resolve!(%__MODULE__{} = item, path) do
    case Library.resolve(item_source(item), path) do
      {:ok, absolute} -> absolute
      {:error, reason} -> raise "unresolvable inbox path: #{inspect(reason)}"
    end
  end

  defp item_source(%__MODULE__{source: %Source{} = source}), do: source
  defp item_source(%__MODULE__{source_id: id}), do: Repo.get!(Source, id)
end
