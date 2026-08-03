defmodule Ambry.Inbox.Draft.SeriesLink do
  @moduledoc """
  One proposed series membership, with its number.

  Each series is its own decision, which is what fixes the standing complaint
  that the import forms take all series or none — Goodreads-shaped sources
  list both "The Expanse" and "The Expanse (Chronological)", and only one of
  those belongs on the book.

  ## The number never auto-resolves without a source

  `Approval` used to default `book_number` to `1` whenever tags carried no
  number, and only 36% of releases carry a series tag at all — so most
  series-bearing imports silently became "book 1". A missing number is a
  question for the operator, not a value to invent.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key false

  embedded_schema do
    field :name, :string
    field :mode, Ecto.Enum, values: [:link, :create], default: :create
    field :series_id, :id

    field :number, :string
    field :source, :string
    field :approved, :boolean, default: false

    embeds_many :candidates, __MODULE__.Match, on_replace: :delete
  end

  defmodule Match do
    @moduledoc "An existing series this proposal could mean."

    use Ecto.Schema

    import Ecto.Changeset

    @primary_key false

    embedded_schema do
      field :series_id, :id
      field :name, :string
      field :exact, :boolean, default: false
    end

    @doc false
    def changeset(match, attrs), do: cast(match, attrs, [:series_id, :name, :exact])
  end

  @doc false
  def changeset(series_link, attrs) do
    series_link
    |> cast(attrs, [:name, :mode, :series_id, :number, :source, :approved])
    |> validate_required([:name])
    |> cast_embed(:candidates)
    |> validate_number()
    |> validate_link()
  end

  defp validate_number(changeset) do
    case get_field(changeset, :number) do
      nil ->
        changeset

      number ->
        case Decimal.parse(number) do
          {_decimal, ""} -> changeset
          _unparseable -> add_error(changeset, :number, "isn't a number")
        end
    end
  end

  defp validate_link(changeset) do
    if get_field(changeset, :mode) == :link do
      validate_required(changeset, [:series_id])
    else
      changeset
    end
  end

  @doc """
  Whether this membership still needs a human.

  A number is required to be *settled*, not to be present: "this book has no
  number in this series" is a real answer, and waiving it is an approval.
  """
  def resolved?(%__MODULE__{approved: true, mode: :link, series_id: id}), do: not is_nil(id)
  def resolved?(%__MODULE__{approved: true, mode: :create, name: name}), do: not is_nil(name)
  def resolved?(%__MODULE__{}), do: false

  def state(%__MODULE__{} = link) do
    cond do
      resolved?(link) -> :approved
      is_nil(link.number) -> :missing
      true -> :unconfirmed
    end
  end

  @doc "The number as the database wants it, or nil for an unnumbered membership."
  def decimal(%__MODULE__{number: nil}), do: nil

  def decimal(%__MODULE__{number: number}) do
    case Decimal.parse(number) do
      {decimal, ""} -> decimal
      _unparseable -> nil
    end
  end
end
