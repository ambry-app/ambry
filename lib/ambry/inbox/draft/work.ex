defmodule Ambry.Inbox.Draft.Work do
  @moduledoc """
  Which Book this release is a recording of, and — when it's a new one — what
  that Book should say.

  This is the pivot of the whole form: linking to a Book already in the
  library makes every work-level field inherited rather than decided, and
  reusing the work is what stops a second recording of it splitting the
  library in two.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Ambry.Inbox.Draft.Credit
  alias Ambry.Inbox.Draft.Field
  alias Ambry.Inbox.Draft.SeriesLink
  alias Ambry.Inbox.Draft.SourceRef

  @primary_key false

  embedded_schema do
    field :mode, Ecto.Enum, values: [:link, :create], default: :create
    field :book_id, :id
    field :approved, :boolean, default: false

    # Whether a human settled the identity, as opposed to the seeder settling
    # it because there was no local hit at the time. The same distinction
    # `Field` and `Credit` draw, for the same reason: `Seed.relink/2` must be
    # free to re-point an identity the seeder defaulted when the library
    # gains the book, and must never move one the operator chose.
    field :curated, :boolean, default: false

    field :confidence, :float
    field :query, :string
    field :query_fields, :map, default: %{}

    # Why no record was adopted, the same as the recording level. Ticking the
    # top record whatever the score says lets a weak match fill in the title,
    # date and authors of a book it isn't about, and say nothing about having
    # done so.
    field :doubt, Ecto.Enum, values: [:none, :nothing_found, :low_confidence]
    field :doubt_detail, :string

    # Whether a human has ticked/unticked records at this level, as opposed to
    # the seeder ticking the top group. `sources` and `approved` can't carry
    # the distinction — the seeder writes both — and `Draft.curated?/1` needs
    # it, or a re-match rebuilds a draft whose only curation was the ticking.
    # Same name and reason as `PersonDecision.evidence_curated`.
    field :evidence_curated, :boolean, default: false

    # Which provider records describe this book. The records live on the
    # item's `matches` because they're evidence; which of them count is a
    # decision, so it lives here.
    embeds_many :sources, SourceRef, on_replace: :delete

    embeds_one :title, Field, on_replace: :update
    embeds_one :published, Field, on_replace: :update

    embeds_many :authors, Credit, on_replace: :delete
    embeds_many :series, SeriesLink, on_replace: :delete
  end

  @doc false
  def changeset(work, attrs) do
    work
    |> cast(attrs, [
      :mode,
      :book_id,
      :approved,
      :curated,
      :evidence_curated,
      :confidence,
      :query,
      :query_fields,
      :doubt,
      :doubt_detail
    ])
    |> cast_embed(:sources)
    |> cast_embed(:title)
    |> cast_embed(:published)
    |> cast_embed(:authors)
    |> cast_embed(:series)
    |> validate_link()
  end

  defp validate_link(changeset) do
    if get_field(changeset, :mode) == :link do
      validate_required(changeset, [:book_id])
    else
      changeset
    end
  end

  @doc """
  Everything about this work that still needs a human.

  When linking, the Book belongs to the library and nothing about it is
  decided here: the only question is the identity itself. Series memberships
  are not proposed on a linked book either, which would make series the one
  editable field on a book the form says it will not touch.
  """
  def unresolved(%__MODULE__{mode: :link} = work) do
    identity(work)
  end

  def unresolved(%__MODULE__{mode: :create} = work) do
    identity(work) ++
      doubted(work) ++
      unresolved_field(work.title, "Title") ++
      unresolved_field(work.published, "First published") ++
      unresolved_in(work.authors, &Credit.resolved?/1, "Author") ++
      unresolved_in(work.series, &SeriesLink.resolved?/1, "Series")
  end

  # A doubted match adopts nothing, so the fields below it are empty or
  # tag-derived. Saying so is what stops "the provider found nothing" and "the
  # provider found something we don't believe" looking identical.
  defp doubted(%__MODULE__{doubt: :low_confidence}),
    do: [%{section: :work, label: "Book records", state: :unconfirmed}]

  defp doubted(%__MODULE__{}), do: []

  defp identity(%__MODULE__{approved: true}), do: []

  defp identity(%__MODULE__{}),
    do: [%{section: :work, label: "Whether this is a book you already have", state: :unconfirmed}]

  defp unresolved_field(nil, _label), do: []

  defp unresolved_field(field, label) do
    if Field.resolved?(field),
      do: [],
      else: [%{section: :work, label: label, state: Field.state(field)}]
  end

  defp unresolved_in(items, resolved?, label) do
    items
    # a tombstoned row is an answered question, not an outstanding one
    |> Enum.reject(&(&1.removed or resolved?.(&1)))
    |> Enum.map(&%{section: :work, label: "#{label}: #{&1.name}", state: state_of(&1)})
  end

  defp state_of(%Credit{} = credit), do: Credit.state(credit)
  defp state_of(%SeriesLink{} = link), do: SeriesLink.state(link)

  @doc """
  Whether the operator has said no record here describes this book.

  The work level's mirror of `Recording.uncatalogued?/1`, and read the same
  way: they touched the evidence and left nothing ticked, which is an answer.
  Reading it off `sources == []` alone would claim the answer had been given
  on every freshly matched item that happened to find nothing.
  """
  def uncatalogued?(%__MODULE__{sources: [], evidence_curated: true}), do: true
  def uncatalogued?(%__MODULE__{}), do: false

  @doc """
  Whether the operator has said this provider record describes the book.
  """
  def uses?(%__MODULE__{sources: sources}, record),
    do: Enum.any?(sources, &SourceRef.points_at?(&1, record))
end
