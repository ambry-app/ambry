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

  @primary_key false

  embedded_schema do
    field :mode, Ecto.Enum, values: [:link, :create], default: :create
    field :book_id, :id
    field :approved, :boolean, default: false

    # the ranked work-level candidate list from auto-match, kept whole
    field :candidates, {:array, :map}, default: []
    field :confidence, :float
    field :query, :string
    field :query_fields, :map, default: %{}

    # WHICH candidate the fields below were filled from. Without it the form
    # could only ask "is this a new book or an existing one?", so every
    # provider row rendered as chosen and clicking one changed nothing
    # visible. Ids are held as strings because a local candidate's is an
    # integer and a provider's is not.
    field :selected_source, :string
    field :selected_id, :string

    embeds_one :title, Field, on_replace: :update
    embeds_one :published, Field, on_replace: :update
    embeds_one :published_format, Field, on_replace: :update

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
      :candidates,
      :confidence,
      :query,
      :query_fields,
      :selected_source,
      :selected_id
    ])
    |> cast_embed(:title)
    |> cast_embed(:published)
    |> cast_embed(:published_format)
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

  When linking, the Book's own fields and credits belong to the existing
  record and are not decided here — only the identity is, plus any *additive*
  series membership the import proposes that the book doesn't already have.
  That is the fill-gaps rule: an import may fill a blank, never overwrite
  curation.
  """
  def unresolved(%__MODULE__{mode: :link} = work) do
    identity(work) ++ unresolved_in(work.series, &SeriesLink.resolved?/1, "Series")
  end

  def unresolved(%__MODULE__{mode: :create} = work) do
    identity(work) ++
      unresolved_field(work.title, "Title") ++
      unresolved_field(work.published, "First published") ++
      unresolved_field(work.published_format, "Date display format") ++
      unresolved_in(work.authors, &Credit.resolved?/1, "Author") ++
      unresolved_in(work.series, &SeriesLink.resolved?/1, "Series")
  end

  defp identity(%__MODULE__{approved: true}), do: []
  defp identity(%__MODULE__{}), do: [%{section: :work, label: "Which book", state: :unconfirmed}]

  defp unresolved_field(nil, _label), do: []

  defp unresolved_field(field, label) do
    if Field.resolved?(field),
      do: [],
      else: [%{section: :work, label: label, state: Field.state(field)}]
  end

  defp unresolved_in(items, resolved?, label) do
    items
    |> Enum.reject(resolved?)
    |> Enum.map(&%{section: :work, label: "#{label}: #{&1.name}", state: state_of(&1)})
  end

  defp state_of(%Credit{} = credit), do: Credit.state(credit)
  defp state_of(%SeriesLink{} = link), do: SeriesLink.state(link)

  @doc """
  Whether a candidate is the one this work's fields were filled from.

  Exactly one can be, which is the whole point: the candidate list is a
  question with one right answer, not a set of things that all matched.
  """
  def selected?(%__MODULE__{selected_source: nil}, _candidate), do: false

  def selected?(%__MODULE__{} = work, candidate) do
    work.selected_source == candidate["source"] and
      work.selected_id == to_string(candidate["id"])
  end
end
