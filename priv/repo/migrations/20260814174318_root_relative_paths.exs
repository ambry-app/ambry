defmodule Ambry.Repo.Migrations.RootRelativePaths do
  @moduledoc """
  Removes absolute paths from the database (PATHS_REFACTOR_PLAN §5.3–§5.4).

  Every served file lives in a library root, so every stored path becomes
  relative to one — a `library_root_id` FK plus a relative string. The one
  exception is the legacy uploads tree, which keeps the convention four
  columns already use: a `/uploads/...` path with a null FK, resolved
  through `Ambry.Paths`.

  The backfill maps each absolute path by longest-prefix match against the
  registered roots. Fail-loud is per column:

    * `media_tracks.path` — a serving path; must resolve. Tracks pointing
      outside every root and outside the uploads tree are deleted first:
      staging has two, written by the admin scan button from legacy
      `source_files`, so they point into the downloads folder. Those
      recordings keep their legacy outputs; Phase 4's relink gives them
      real placements.
    * `media.source_path` — must resolve; legacy ones are all under the
      uploads tree and become `/uploads/...`.
    * `media.source_files` — legacy recordings point into a *downloads*
      folder, which is a source, not a root. They are provenance, not
      serving paths, so anything unmatched is quarantined into
      `legacy_source_files` (absolute, nullable) for Phase 4 to drain.
  """

  use Ecto.Migration

  import Ecto.Query

  def up do
    alter table(:media) do
      add :library_root_id, references(:library_roots)
      add :legacy_source_files, {:array, :text}
    end

    alter table(:media_tracks) do
      add :library_root_id, references(:library_roots)
    end

    flush()

    roots = repo().all(from(r in "library_roots", select: %{id: r.id, path: r.path}))
    uploads = Application.fetch_env!(:ambry, :uploads_path)

    backfill_tracks(roots, uploads)
    backfill_media(roots, uploads)
  end

  def down do
    # Best-effort: restore absolute paths from the FK (and the uploads
    # config) before dropping it.
    roots = repo().all(from(r in "library_roots", select: %{id: r.id, path: r.path}))
    uploads = Application.fetch_env!(:ambry, :uploads_path)

    repo().update_all(
      from(t in "media_tracks",
        where: like(t.path, "/uploads/%"),
        update: [set: [path: fragment("? || substring(path from 9)", ^uploads)]]
      ),
      []
    )

    repo().update_all(
      from(m in "media",
        where: like(m.source_path, "/uploads/%"),
        update: [set: [source_path: fragment("? || substring(source_path from 9)", ^uploads)]]
      ),
      []
    )

    for root <- roots do
      repo().update_all(
        from(t in "media_tracks",
          where: t.library_root_id == ^root.id,
          update: [set: [path: fragment("? || '/' || path", ^root.path)]]
        ),
        []
      )

      repo().update_all(
        from(m in "media",
          where: m.library_root_id == ^root.id,
          update: [
            set: [
              source_path: fragment("? || '/' || source_path", ^root.path),
              source_files:
                fragment(
                  "(SELECT coalesce(array_agg(? || '/' || f ORDER BY ord), '{}') FROM unnest(source_files) WITH ORDINALITY AS u(f, ord))",
                  ^root.path
                )
            ]
          ]
        ),
        []
      )
    end

    repo().update_all(
      from(m in "media",
        where: not is_nil(m.legacy_source_files),
        update: [set: [source_files: m.legacy_source_files]]
      ),
      []
    )

    alter table(:media) do
      remove :library_root_id
      remove :legacy_source_files
    end

    alter table(:media_tracks) do
      remove :library_root_id
    end
  end

  defp backfill_tracks(roots, uploads) do
    tracks = repo().all(from(t in "media_tracks", select: %{id: t.id, path: t.path}))

    for track <- tracks do
      case classify(track.path, roots, uploads) do
        {:root, root, relative} ->
          repo().update_all(from(t in "media_tracks", where: t.id == ^track.id),
            set: [path: relative, library_root_id: root.id]
          )

        {:uploads, web} ->
          repo().update_all(from(t in "media_tracks", where: t.id == ^track.id),
            set: [path: web]
          )

        :elsewhere ->
          # A serving path outside every root has no place in the new model.
          # The recording falls back to its legacy outputs; Phase 4 relinks.
          repo().delete_all(from(t in "media_tracks", where: t.id == ^track.id))
      end
    end
  end

  defp backfill_media(roots, uploads) do
    media =
      repo().all(
        from(m in "media",
          select: %{id: m.id, source_path: m.source_path, source_files: m.source_files}
        )
      )

    for row <- media do
      {source_path, root_id} = media_source_path(row, roots, uploads)
      {source_files, legacy_source_files} = split_source_files(row.source_files, roots, uploads)

      repo().update_all(from(m in "media", where: m.id == ^row.id),
        set: [
          source_path: source_path,
          library_root_id: root_id,
          source_files: source_files,
          legacy_source_files: legacy_source_files
        ]
      )
    end
  end

  defp media_source_path(%{source_path: nil}, _roots, _uploads), do: {nil, nil}

  defp media_source_path(%{source_path: path, id: id}, roots, uploads) do
    case classify(path, roots, uploads) do
      {:root, root, relative} -> {relative, root.id}
      {:uploads, web} -> {web, nil}
      :elsewhere -> raise "media #{id}: source_path resolves to no root or uploads: #{path}"
    end
  end

  # Order is play order and is preserved; the split is stable because a
  # recording's files share one folder, so they all land on one side.
  defp split_source_files(nil, _roots, _uploads), do: {[], nil}

  defp split_source_files(files, roots, uploads) do
    {resolved, legacy} =
      files
      |> Enum.map(fn file ->
        case classify(file, roots, uploads) do
          {:root, _root, relative} -> {:resolved, relative}
          {:uploads, web} -> {:resolved, web}
          :elsewhere -> {:legacy, file}
        end
      end)
      |> Enum.split_with(&match?({:resolved, _}, &1))

    {Enum.map(resolved, &elem(&1, 1)),
     case Enum.map(legacy, &elem(&1, 1)) do
       [] -> nil
       some -> some
     end}
  end

  defp classify(path, roots, uploads) do
    match =
      roots
      |> Enum.filter(&String.starts_with?(path, &1.path <> "/"))
      |> Enum.max_by(&String.length(&1.path), fn -> nil end)

    cond do
      match ->
        {:root, match, Path.relative_to(path, match.path)}

      String.starts_with?(path, "/uploads/") ->
        {:uploads, path}

      String.starts_with?(path, uploads <> "/") ->
        {:uploads, "/uploads/" <> Path.relative_to(path, uploads)}

      true ->
        :elsewhere
    end
  end
end
