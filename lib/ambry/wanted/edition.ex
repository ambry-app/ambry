defmodule Ambry.Wanted.Edition do
  @moduledoc """
  A provider's record of one audiobook recording, copied out of the provider
  and frozen.

  This is deliberately a value, not a row: it is *what the operator chose*,
  and it has to keep rendering after the provider revises the listing, pulls
  it, or simply cannot be reached. Everything here is optional except the
  title, because provider coverage is genuinely patchy — measured across the
  ten audio editions Hardcover holds for *Neuromancer*: cover 9, date 9,
  publisher 8, narrators 6, **ASIN 2**.

  Which is also why `asin` is a field like any other rather than the key. See
  `Ambry.Wanted.Watch` for the identity that is used instead.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @derive Jason.Encoder
  @primary_key false
  embedded_schema do
    field :title, :string
    field :authors, {:array, :string}, default: []
    field :narrators, {:array, :string}, default: []
    field :publisher, :string
    field :language, :string
    field :cover_url, :string
    field :description, :string

    # How long the recording is. This is an audiobook, so its runtime is part
    # of what it *is* — it is what separates an abridgement from the full
    # reading and one dramatization from another when the title, the author
    # and even the narrator all agree.
    field :duration_seconds, :integer

    # Matching keys, none of them required, all of them useful when the
    # recording eventually turns up in the inbox.
    field :asin, :string
    field :isbn13, :string
  end

  @fields ~w(title authors narrators publisher language cover_url description
             duration_seconds asin isbn13)a

  @doc false
  def changeset(edition, attrs) do
    edition
    |> cast(attrs, @fields)
    |> validate_required([:title])
  end

  @doc """
  Builds an edition from a provider's normalized book struct.

  `Ambry.Metadata.Provider.Book` is the shape both levels answer in — an
  Audible product *is* a recording, and a Hardcover audio edition is one too
  — so one function covers both.
  """
  def from_provider_book(%{__struct__: _} = book) do
    %__MODULE__{
      title: book.title,
      authors: names(Map.get(book, :authors)),
      narrators: names(Map.get(book, :narrators)),
      publisher: Map.get(book, :publisher),
      language: Map.get(book, :language),
      cover_url: Map.get(book, :cover_url),
      description: Map.get(book, :description),
      duration_seconds: Map.get(book, :duration_seconds),
      asin: Map.get(book, :asin)
    }
  end

  defp names(nil), do: []
  defp names(list), do: Enum.map(list, & &1.name)

  @doc """
  The runtime in words, or nil when the provider did not give one.

  Hours and minutes, because that is how long an audiobook is talked about —
  nobody asks for a recording in seconds.
  """
  def runtime(%__MODULE__{duration_seconds: nil}), do: nil

  def runtime(%__MODULE__{duration_seconds: seconds}) do
    hours = div(seconds, 3600)
    minutes = seconds |> rem(3600) |> div(60)

    case {hours, minutes} do
      {0, 0} -> nil
      {0, m} -> "#{m}m"
      {h, 0} -> "#{h}h"
      {h, m} -> "#{h}h #{m}m"
    end
  end

  @doc "The credited authors as one phrase, or nil when the provider named none."
  def byline(%__MODULE__{authors: []}), do: nil
  def byline(%__MODULE__{authors: authors}), do: Enum.join(authors, ", ")

  @doc """
  The narrators as one phrase.

  Absent narrators are reported as absent rather than papered over: a
  recording with no named reader is a gap in the provider's record, and
  saying so is what lets the operator judge the candidate.
  """
  def narrated_by(%__MODULE__{narrators: []}), do: nil
  def narrated_by(%__MODULE__{narrators: narrators}), do: Enum.join(narrators, ", ")
end
