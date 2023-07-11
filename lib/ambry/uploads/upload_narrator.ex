defmodule Ambry.Uploads.UploadNarrator do
  @moduledoc """
  Join table between media and narrators.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Ambry.Narrators.Narrator
  alias Ambry.Uploads.Upload

  schema "upload_narrators" do
    belongs_to :upload, Upload
    belongs_to :narrator, Narrator
  end

  @doc false
  def changeset(upload_narrator, attrs) do
    upload_narrator
    |> cast(attrs, [:narrator_id])
    |> cast_assoc(:narrator)
  end
end
