defmodule AmbryWeb.Admin.Revert do
  @moduledoc """
  The way back out of a chip: what a field would return to, and the params
  that put it there.

  A proposal chip changes a field in one click, and until this existed the
  only way to undo that click was reloading the page — which throws away
  every other edit on the form. So the saved value is offered as one more
  option in the same row, ghost rather than lime, and only while the field
  differs from it.

  Deliberately scalars only. Reverting a list of authors or narrators means
  putting back rows that may have been created since, which is a different
  question from "put this value back" and not one a chip should imply it can
  answer.

  New vocabulary rather than the import form's: an import has nothing saved
  to go back to, so there was nothing to be consistent with.
  """

  alias Ecto.Changeset

  @doc """
  What the field would go back to, or `nil` when it is already there.

  Returns `%{display: binary}` — plus `:image` when the value is a picture,
  because choosing a cover is the one decision on these forms where words are
  the wrong answer.
  """
  def offer(form, record, :image) do
    params = form.params

    changed? =
      params["image_type"] in ["url_import", "embedded"] or
        to_string(params["image_path"] || record.image_path || "") !=
          to_string(record.image_path || "")

    if changed?, do: %{display: display(record.image_path), image: record.image_path}
  end

  # Both halves or neither: a date and its precision are one decision on these
  # forms, exactly as the chips propose them.
  def offer(form, record, :published) do
    current =
      {Changeset.get_field(form.source, :published),
       Changeset.get_field(form.source, :published_format)}

    if current != {record.published, record.published_format},
      do: %{display: display(record.published)}
  end

  def offer(form, record, field) do
    saved = Map.fetch!(record, field)

    if to_string(Changeset.get_field(form.source, field) || "") != to_string(saved || ""),
      do: %{display: display(saved)}
  end

  @doc """
  The form params that put the field back.
  """
  # Back to the picture on the record, and back to the picker's resting state:
  # leaving `url_import` selected would re-import on the next save.
  def params(record, :image) do
    %{
      "image_path" => record.image_path,
      "image_type" => "upload",
      "image_import_url" => ""
    }
  end

  def params(record, :published) do
    %{
      "published" => record.published,
      "published_format" => record.published_format
    }
  end

  def params(record, field), do: %{to_string(field) => Map.fetch!(record, field)}

  @doc """
  Every field's offer, for a record that has been saved.

  A form creating a record has nothing to go back to, so it gets nothing.
  """
  def offers(form, record, fields) do
    if record && record.id,
      do: Map.new(fields, &{&1, offer(form, record, &1)}),
      else: %{}
  end

  defp display(nil), do: "nothing"
  defp display(%Date{} = date), do: Date.to_iso8601(date)
  defp display(value) when is_binary(value), do: truncate(value)
  defp display(value), do: to_string(value)

  defp truncate(value) when byte_size(value) > 40, do: String.slice(value, 0, 37) <> "…"
  defp truncate(value), do: value
end
