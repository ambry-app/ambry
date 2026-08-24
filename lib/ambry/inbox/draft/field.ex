defmodule Ambry.Inbox.Draft.Field do
  @moduledoc """
  One scalar decision: a value, where it came from, and whether it's settled.

  Values are held as strings regardless of their eventual type, because a
  draft's other half is an HTML form; approval casts them once, where they
  become real columns.

  `candidates` is what the sources proposed, kept whole rather than reduced to
  a winner, so "show me the alternatives" costs nothing.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Ambry.Inbox.Draft.Candidate

  @manual "manual"

  @primary_key false

  embedded_schema do
    field :value, :string
    field :source, :string
    # the provider record behind `source`, when there is one (see Candidate)
    field :record, :string
    # date fields only: the display precision that belongs to `value` — one
    # composite fact, one decision (see Candidate.format)
    field :format, :string
    field :approved, :boolean, default: false
    field :required, :boolean, default: false

    # Which candidate was taken. `source` alone can't say: two records from
    # one provider are two proposals with one source.
    field :chosen_key, :string

    # Whether a *human* settled this, as opposed to the seeder settling it
    # because there was only one thing on offer: re-derivation must not move
    # a value somebody chose, and must be free to move one nobody did.
    # `chosen_key` cannot answer it, since the seeder sets that too.
    field :curated, :boolean, default: false

    embeds_many :candidates, Candidate, on_replace: :delete
  end

  @doc false
  def changeset(field, attrs) do
    field
    |> cast(attrs, [
      :value,
      :source,
      :record,
      :format,
      :approved,
      :required,
      :chosen_key,
      :curated
    ])
    |> full_when_day_known()
    |> cast_embed(:candidates)
    |> track_manual_edit(attrs)
    |> validate_settled()
  end

  # Typing a value is the decision: it records `manual` and locks, while
  # accepting a provider's suggestion records that provider and stays open to
  # a future refresh.
  defp track_manual_edit(changeset, attrs) do
    explicit_source? = Map.has_key?(attrs, "source") or Map.has_key?(attrs, :source)

    case fetch_change(changeset, :value) do
      {:ok, _value} when not explicit_source? ->
        changeset
        |> put_change(:source, @manual)
        |> put_change(:chosen_key, @manual)
        |> put_change(:approved, true)
        |> put_change(:curated, true)

      _unchanged_or_sourced ->
        changeset
    end
  end

  # A required field cannot be waived: the form would otherwise approve its
  # way past a missing title and fail deep inside the import transaction.
  defp validate_settled(changeset) do
    required? = get_field(changeset, :required)
    approved? = get_field(changeset, :approved)
    blank? = get_field(changeset, :value) in [nil, ""]

    if required? and approved? and blank? do
      add_error(changeset, :value, "is needed before this can be imported")
    else
      changeset
    end
  end

  @doc """
  The operator's edit: a typed value with no provider behind it, which settles
  the field.
  """
  def edit(%__MODULE__{} = field, value) do
    value = presence(value)

    %{
      field
      | value: value,
        source: "manual",
        chosen_key: "manual",
        curated: true,
        # Clearing the box is the first half of retyping, so a required
        # field un-settles rather than becoming approved-and-empty. Clearing
        # an optional one is a real answer and stays settled.
        approved: not (field.required and is_nil(value))
    }
  end

  @doc """
  Accepts one of the proposed candidates, recording which one.
  """
  def choose(%__MODULE__{} = field, key) do
    case Enum.find(field.candidates, &(&1.key == key)) do
      nil -> field
      # Picking a chip is a human answering, so it survives re-derivation;
      # `take/2` alone is the seeder settling a field and stays movable.
      candidate -> %{take(field, candidate) | curated: true}
    end
  end

  @doc """
  Settles the field on a proposal: the one place a candidate becomes a
  field's value.

  A hand-rolled version that forgets `chosen_key` renders as a filled box
  with no chip highlighted, which is settled to the model and unsettled to
  the eye.
  """
  def take(%__MODULE__{} = field, %Candidate{} = candidate) do
    %{
      field
      | value: candidate.value,
        source: candidate.source,
        record: candidate.record,
        format: candidate.format,
        chosen_key: candidate.key,
        approved: true
    }
  end

  # Points the chip at the record that said so where one did, so the operator
  # sees an answer with a provider behind it rather than a bare value.
  @doc "Whether this candidate is the one the field took."
  def chose?(%__MODULE__{chosen_key: nil}, _candidate), do: false
  def chose?(%__MODULE__{} = field, candidate), do: field.chosen_key == candidate.key

  @doc """
  Settles the field as deliberately empty: an approval, not an omission.
  """
  def waive(%__MODULE__{} = field),
    do: %{
      field
      | value: nil,
        source: nil,
        record: nil,
        format: nil,
        chosen_key: nil,
        approved: true,
        curated: true
    }

  @doc """
  Whether this field still needs a human.
  """
  def resolved?(%__MODULE__{approved: true}), do: true
  def resolved?(%__MODULE__{}), do: false

  @doc """
  Why it isn't resolved, for the operator-facing unresolved list.

  Counts *distinct* proposals, so `:ambiguous` genuinely means the sources
  disagree rather than that there are several records.
  """
  def state(%__MODULE__{approved: true}), do: :approved

  def state(%__MODULE__{} = field) do
    field.candidates
    |> Enum.map(& &1.value)
    |> Enum.uniq()
    |> case do
      [] -> if field.required, do: :missing, else: :unconfirmed
      [_one] -> :unconfirmed
      _several -> :ambiguous
    end
  end

  @doc """
  The settled value, as the string it's staged as.
  """
  def value(nil), do: nil
  def value(%__MODULE__{value: value}), do: presence(value)

  @doc """
  The settled value as a `Date`, or nil for anything unparseable — a data
  problem for the changeset to report, not a crash mid-transaction.
  """
  def date(nil), do: nil

  def date(%__MODULE__{value: value}) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> date
      {:error, _reason} -> nil
    end
  end

  def date(%__MODULE__{}), do: nil

  # A newly typed date whose day is not the first is a full date, so a date
  # edit drags a stale precision along. Only the date's own change triggers
  # it, so a precision set deliberately is never overruled.
  defp full_when_day_known(changeset) do
    value = Ecto.Changeset.get_change(changeset, :value)
    format_changed? = Map.has_key?(changeset.changes, :format)
    format = Ecto.Changeset.get_field(changeset, :format)

    with false <- format_changed?,
         true <- is_binary(value) and format not in [nil, "full"],
         {:ok, %Date{day: day}} when day != 1 <- Date.from_iso8601(value) do
      Ecto.Changeset.put_change(changeset, :format, "full")
    else
      _ambiguous_or_deliberate -> changeset
    end
  end

  @doc """
  The display precision riding a date field, as the atom the schemas store.
  """
  def format_atom(nil, default), do: default

  def format_atom(%__MODULE__{format: format}, default) do
    case format do
      "full" -> :full
      "year_month" -> :year_month
      "year" -> :year
      _unknown -> default
    end
  end

  @doc """
  The settled value as an existing atom, for `Ecto.Enum` columns.

  Never mints one: a draft is operator input.
  """
  def atom(field, default) do
    case value(field) do
      nil ->
        default

      value ->
        try do
          String.to_existing_atom(value)
        rescue
          ArgumentError -> default
        end
    end
  end

  defp presence(nil), do: nil
  defp presence(string) when is_binary(string), do: with("" <- String.trim(string), do: nil)
  defp presence(other), do: other
end
