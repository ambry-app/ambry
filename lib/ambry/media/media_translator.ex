defmodule Ambry.Media.MediaTranslator do
  @moduledoc """
  Join table between media and authors crediting the translator(s) of a
  recording's text.

  Translators are Author identities (reusing the pen-name machinery — a
  translator like Ken Liu is also an author).
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Ambry.Media.Media
  alias Ambry.People.Author

  schema "media_translators" do
    belongs_to :media, Media
    belongs_to :author, Author

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(media_translator, attrs) do
    media_translator
    |> cast(attrs, [:author_id])
    |> validate_required(:author_id)
    |> unique_constraint([:media_id, :author_id])
  end
end
