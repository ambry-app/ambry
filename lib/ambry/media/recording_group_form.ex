defmodule Ambry.Media.RecordingGroupForm do
  @moduledoc """
  The group admin form's shape: the group's own facts plus its members,
  editable inline exactly like a series' books.

  A membership "row" here is really a media row's `recording_group_id` +
  `part_number` — media⇄group has no join table — so this embedded schema
  exists to give the form the same `inputs_for` mechanics the series form
  gets from `series_books`, while the save path writes the member diff
  through `Ambry.Media.update_media/3` (keeping search, sync, PubSub and
  the orphan sweep honest).
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Ambry.Media.RecordingGroup

  @primary_key false

  embedded_schema do
    field :name, :string
    field :book_id, :id
    field :parts_total, :integer
    field :show_label, :boolean, default: false
    field :part_word, :string
    field :part_word_plural, :string

    embeds_many :members, __MODULE__.Member, on_replace: :delete
  end

  defmodule Member do
    @moduledoc "One recording's membership: which media, at which position."

    use Ecto.Schema

    import Ecto.Changeset

    @primary_key false

    embedded_schema do
      field :media_id, :id
      field :part_number, :integer
    end

    @doc false
    def changeset(member, attrs) do
      member
      |> cast(attrs, [:media_id, :part_number])
      |> validate_required([:media_id])
      |> validate_number(:part_number, greater_than_or_equal_to: 1)
    end
  end

  @doc "The form's starting state for a group (members in part order)."
  def from_group(%RecordingGroup{} = group) do
    members =
      case group.media do
        media when is_list(media) ->
          Enum.map(media, &%Member{media_id: &1.id, part_number: &1.part_number})

        _not_loaded ->
          []
      end

    %__MODULE__{
      name: group.name,
      book_id: group.book_id,
      parts_total: group.parts_total,
      show_label: group.show_label,
      part_word: group.part_word,
      part_word_plural: group.part_word_plural,
      members: members
    }
  end

  @doc false
  def changeset(form, attrs) do
    form
    |> cast(attrs, [:name, :book_id, :parts_total, :show_label, :part_word, :part_word_plural])
    |> cast_embed(:members,
      with: &__MODULE__.Member.changeset/2,
      sort_param: :members_sort,
      drop_param: :members_drop
    )
    |> update_change(:part_word, &downcase_word/1)
    |> update_change(:part_word_plural, &downcase_word/1)
    |> validate_required([:name, :book_id])
    |> validate_number(:parts_total, greater_than_or_equal_to: 1)
    |> validate_members()
  end

  defp downcase_word(nil), do: nil
  defp downcase_word(word), do: word |> String.trim() |> String.downcase() |> presence()

  defp presence(""), do: nil
  defp presence(word), do: word

  # Two kinds of nonsense a row can hold: the same recording twice, and a
  # position past the set's total. Errors land on the offending row (so the
  # form points at it) AND on the parent (child errors added after
  # `cast_embed` don't flip the parent's validity on their own).
  defp validate_members(changeset) do
    total = get_field(changeset, :parts_total)

    case fetch_change(changeset, :members) do
      {:ok, members} ->
        {members, problems} = mark_member_problems(members, total)

        changeset = put_change(changeset, :members, members)
        if problems == [], do: changeset, else: add_error(changeset, :members, hd(problems))

      :error ->
        changeset
    end
  end

  defp mark_member_problems(members, total) do
    {members, {_seen, problems}} =
      Enum.map_reduce(members, {MapSet.new(), []}, fn member, {seen, problems} ->
        id = get_field(member, :media_id)
        part = get_field(member, :part_number)

        cond do
          # Members have no primary key, so cast_embed replaces the whole
          # list — a :replace row is on its way out, not a duplicate of the
          # row taking its place.
          member.action == :replace ->
            {member, {seen, problems}}

          id && MapSet.member?(seen, id) ->
            {add_error(member, :media_id, "is already in the set"),
             {seen, ["a recording is listed twice" | problems]}}

          part && total && part > total ->
            {add_error(member, :part_number, "is past the total"),
             {put_seen(seen, id), ["a part number is past the total" | problems]}}

          true ->
            {member, {put_seen(seen, id), problems}}
        end
      end)

    {members, Enum.reverse(problems)}
  end

  defp put_seen(seen, nil), do: seen
  defp put_seen(seen, id), do: MapSet.put(seen, id)
end
