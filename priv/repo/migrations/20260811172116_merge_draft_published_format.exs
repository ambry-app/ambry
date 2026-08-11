defmodule Ambry.Repo.Migrations.MergeDraftPublishedFormat do
  @moduledoc """
  A date and its display precision became one composite field: the draft's
  `published` field (work and recording levels) now carries `format`, and
  the separate `published_format` field is gone.

  Stored drafts hold the old shape. Loading them without this migration is
  harmless — Ecto ignores the unknown `published_format` key — but the
  precision decisions the operator already made would silently reset to
  "full", so this folds them in: the format field's settled value becomes
  `published.format`, and each date candidate adopts the format its own
  source proposed (matched by source, the way the two lists were built).

  Down puts the format back into a `published_format` field with the same
  settled value; candidate-level detail is not reconstructed.
  """
  use Ecto.Migration

  import Ecto.Query

  def up do
    repo().transaction(fn ->
      from(i in "inbox_items",
        where: not is_nil(i.draft),
        select: {i.id, i.draft}
      )
      |> repo().all()
      |> Enum.each(fn {id, draft} ->
        merged = draft |> merge_level("work") |> merge_level("recording")

        if merged != draft do
          repo().update_all(from(i in "inbox_items", where: i.id == ^id),
            set: [draft: merged]
          )
        end
      end)
    end)
  end

  def down do
    repo().transaction(fn ->
      from(i in "inbox_items",
        where: not is_nil(i.draft),
        select: {i.id, i.draft}
      )
      |> repo().all()
      |> Enum.each(fn {id, draft} ->
        split = draft |> split_level("work") |> split_level("recording")

        if split != draft do
          repo().update_all(from(i in "inbox_items", where: i.id == ^id),
            set: [draft: split]
          )
        end
      end)
    end)
  end

  defp merge_level(draft, level) do
    with %{} = level_map <- draft[level],
         %{} = format_field <- level_map["published_format"] do
      published = level_map["published"] || %{}

      # each date candidate adopts the precision its own source proposed
      format_by_source =
        Map.new(format_field["candidates"] || [], &{&1["source"], &1["value"]})

      candidates =
        for candidate <- published["candidates"] || [] do
          Map.put_new(candidate, "format", format_by_source[candidate["source"]])
        end

      published =
        published
        |> Map.put("format", format_field["value"])
        |> Map.put("candidates", candidates)

      level_map =
        level_map
        |> Map.put("published", published)
        |> Map.delete("published_format")

      Map.put(draft, level, level_map)
    else
      _no_old_shape -> draft
    end
  end

  defp split_level(draft, level) do
    with %{} = level_map <- draft[level],
         %{"format" => format} = published when not is_nil(format) <- level_map["published"] do
      format_field = %{
        "value" => format,
        "source" => published["source"],
        "approved" => published["approved"],
        "required" => false,
        "candidates" => []
      }

      level_map =
        level_map
        |> Map.put("published", Map.delete(published, "format"))
        |> Map.put("published_format", format_field)

      Map.put(draft, level, level_map)
    else
      _no_new_shape -> draft
    end
  end
end
