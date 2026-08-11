defmodule Ambry.Inbox.Draft.Field do
  @moduledoc """
  One scalar decision: a value, where it came from, and whether it's settled.

  Values are held as strings regardless of their eventual type. A draft is a
  staging area whose other half is an HTML form, and strings are what a form
  produces; approval casts them once, at the point where they become real
  columns. Keeping `%Date{}` and `%Decimal{}` in the jsonb would mean casting
  on the way in, on the way out, and again on every re-render.

  `candidates` is what the sources proposed — kept whole rather than reduced
  to a winner, so "show me the alternatives" costs nothing and re-querying is
  only needed when the right answer isn't in the list at all.
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
    # one provider are two proposals with one source, and the form could
    # neither highlight the right chip nor apply the second one.
    field :chosen_key, :string

    # Whether a *human* settled this, as opposed to the seeder settling it
    # because there was only one thing on offer. The same distinction `Credit`
    # and `SeriesLink` already draw, and for the same reason: re-derivation
    # must not move a value somebody chose, and must be free to move one
    # nobody did.
    #
    # `chosen_key` cannot answer this — the seeder sets it too — so keying
    # re-derivation on it made every auto-settled field permanently sticky.
    # Measured on the operator's Becky Chambers file: the title settled from
    # the tags at seed time (nothing else was on offer, the work being
    # doubted), and then ticking the correct record could not dislodge it. The
    # book imported as **"Wayfarers, Book 1"** with the real title sitting
    # un-chosen in the candidate list.
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

  # Typing a value *is* the decision — 1d's lock semantics exactly: editing a
  # value records it as the operator's and locks it, while accepting a
  # provider's suggestion records that provider and stays unlocked so a future
  # refresh may still update it. Without this a field the operator retyped
  # would keep claiming it came from whichever provider proposed the old
  # value, and refresh would later overwrite their correction.
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

  # A required field cannot be waived. Without this the form could approve its
  # way past a missing title or publication date and hand approval a decision
  # it has no way to execute — the failure would surface as a changeset error
  # deep inside the transaction, which is exactly the late surprise the whole
  # decision model exists to eliminate.
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
  The operator's edit: a typed value with no provider behind it.

  Editing is what `1d` calls curation, so the source becomes `manual` and the
  field settles — there is nothing left to decide about a value someone chose
  deliberately.
  """
  def edit(%__MODULE__{} = field, value) do
    value = presence(value)

    %{
      field
      | value: value,
        source: "manual",
        chosen_key: "manual",
        curated: true,
        # Clearing the box is the first half of retyping, and a *required*
        # field cannot be settled as blank — so it un-settles rather than
        # becoming an approved-and-empty value the changeset then refuses to
        # save. Validation gates saving; the invariant gates importing, and
        # conflating the two makes the form unusable. Clearing an optional
        # field is a real answer ("no bio") and stays settled.
        approved: not (field.required and is_nil(value))
    }
  end

  @doc """
  Accepts one of the proposed candidates, recording which one.
  """
  def choose(%__MODULE__{} = field, key) do
    case Enum.find(field.candidates, &(&1.key == key)) do
      nil -> field
      # Picking a chip is a human answering the question, which is what makes
      # it survive re-derivation — `take/2` alone is the seeder settling a
      # field and stays movable.
      candidate -> %{take(field, candidate) | curated: true}
    end
  end

  @doc """
  Settles the field on a proposal.

  The one place a candidate becomes a field's value, because keeping it in one
  place is the only thing that works: hand-rolled versions of these four
  assignments in the seeder and in `Draft.Edit` have each forgotten
  `chosen_key` at least once, and a value whose candidate the field can't name
  renders as a filled box with no chip highlighted — settled to the model,
  unsettled to the eye.
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
  Settles the field as deliberately empty.

  Waiving is an approval, not an omission — it's what makes "every piece is
  resolved" reachable on a record with optional fields nobody filled in.
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

  `:missing` and `:ambiguous` are genuinely different problems — one needs a
  value from somewhere, the other needs a choice between values already in
  hand — and the form should not describe them the same way. Which is exactly
  why this counts *distinct* proposals: it used to report "sources disagree"
  for a field with one proposal, and for a field with none at all.
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
  The settled value as a `Date`.

  Returns nil for anything unparseable rather than raising: a value that got
  this far was approved, and a malformed one is a data problem for the
  changeset to report against the real column, not a crash mid-transaction.
  """
  def date(nil), do: nil

  def date(%__MODULE__{value: value}) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> date
      {:error, _reason} -> nil
    end
  end

  def date(%__MODULE__{}), do: nil

  # A newly typed date whose day is real is a full date — nobody records
  # June 2nd to mean "2011" — so a date edit drags a stale precision along.
  # Only the date's own change triggers it: a precision the operator sets
  # deliberately (format changing, date not) is never overruled, and
  # first-of-month days stay ambiguous and keep what was set.
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

  Only ever converts to atoms that already exist — a draft is operator input,
  and `String.to_atom/1` on operator input leaks the atom table.
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
