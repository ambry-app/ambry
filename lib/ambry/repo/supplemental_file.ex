defmodule Ambry.Repo.SupplementalFile do
  @moduledoc """
  An uploaded file
  """

  use Ecto.Schema

  import Ecto.Changeset

  @derive {Jason.Encoder, only: [:filename, :path]}

  embedded_schema do
    field :filename, :string
    field :label, :string
    field :mime, :string
    field :path, :string
  end

  def changeset(chapter, attrs) do
    chapter
    |> cast(attrs, [:filename, :label, :mime, :path])
    |> validate_required([:filename, :mime, :path])
    |> validate_filename_matches_mime()
  end

  defp validate_filename_matches_mime(changeset) do
    mime = get_field(changeset, :mime)
    valid_extensions = MIME.extensions(mime)

    validate_change(changeset, :filename, fn :filename, filename ->
      extension = filename |> Path.extname() |> String.trim_leading(".")

      if extension in valid_extensions do
        []
      else
        [
          filename:
            "invalid extension for mime-type: #{mime}, use one of: #{Enum.join(valid_extensions)}"
        ]
      end
    end)
  end
end
