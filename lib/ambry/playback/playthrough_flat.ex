defmodule Ambry.Playback.PlaythroughFlat do
  @moduledoc """
  A flattened view of playthroughs.
  """

  use Ambry.Repo.FlatSchema

  @primary_key {:id, :binary_id, autogenerate: false}

  schema "playthroughs_flat" do
    field :user_id, :integer
    field :media_id, :integer
    field :status, Ecto.Enum, values: [:in_progress, :finished, :abandoned, :deleted]
    field :position, :decimal
    field :rate, :decimal
    field :started_at, Ambry.Ecto.UtcDateTimeMs
    field :last_event_at, Ambry.Ecto.UtcDateTimeMs
    field :media_duration, :decimal
    field :media_thumbnail, :string
    field :book_title, :string
    field :progress_percent, :decimal
  end

  def filter(query, :user_id, user_id) do
    from p in query, where: p.user_id == ^user_id
  end

  def filter(query, :search, search_string) do
    search_string = "%#{search_string}%"
    from p in query, where: ilike(p.book_title, ^search_string)
  end
end
