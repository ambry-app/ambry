defmodule Ambry.Inbox.Content do
  @moduledoc """
  Whether the library already holds a file's *bytes*, wherever they sit.

  The inbox ledger's other half asks where a file is: a scanned path, compared
  against the paths the library records. That is the only question a path can
  answer, and it is blind by construction to the same bytes under a different
  name.

  Which the library is full of. Measured against production, 2026-08-16: of
  304 releases in the downloads folder, 40 are **byte-identical copies of
  files the library already holds** — verified by size on all 40 and by
  head+tail digest on a sample. They were imported through the web upload
  form, which *copies* into `source_media/<uuid>/`, so the library's recorded
  source is the copy, the downloads original was never recorded anywhere, and
  sometimes it doesn't even share an extension (`Romancing the Duke` is `.mp4`
  in uploads and `.m4b` in downloads, same 258,479,113 bytes).

  Relinking makes this load-bearing rather than merely tidy. A relinked
  recording may not keep `legacy_source_files` — a placement and that column
  are mutually exclusive by CHECK — so the downloads-side paths it recorded
  stop existing the moment it relinks, and every one of the 204 server-import
  releases would resurface in the queue as brand new.

  ## The test, in the order it is asked

  1. **Size**, from `media_tracks.size`, which is already in the database.
     Free, and fully discriminating on this library: 40 of 40 matched
     completely, zero partial matches, no collisions across 3,707
     downloads-side files. It is a weak promise in principle, so it indexes
     rather than decides.
  2. **Identity** — same device and inode. A hardlinked placement *is* the
     file, and this says so for nothing: no reads, no arguing about digests.
     This is what the server-import era becomes after a relink.
  3. **A head and tail digest**, for genuine copies, which is the only case
     left. It is what turns the size match from a strong hint into an answer.

  Every step after the first runs only for a file whose size already matches
  something, so a release that is genuinely new costs one `stat` and a map
  lookup.

  ## Why the digest window is small

  Discovery runs hourly, and these files never stop being twins — the 40 will
  size-match on every scan for as long as both copies exist. A full digest of
  a 14-hour book, or even the 8MB-a-side one an earlier draft of the reclaim
  plan proposed, is a lot of NFS traffic to pay every hour to re-confirm
  something that has not changed.

  1MB at each end is confirmation, not evidence: the discriminator is the
  exact byte size, and two audiobook files of identical length whose container
  headers, first audio frames and last audio frames all agree are the same
  file. What the digest rules out is the pathological case where size alone
  would have been believed.

  ## What it does not answer

  Legacy recordings that have not been relinked yet — their sources sit in
  `source_media` with no `media_tracks` row and therefore no recorded size, so
  the twins of *those* recordings stay in the queue until the recording is
  relinked, at which point they match here. That is the honest place for the
  queue to heal: as the reclaim proceeds, not by walking the whole uploads NAS
  once an hour to find out something the reclaim is about to make true anyway.
  """

  import Ecto.Query

  alias Ambry.Library
  alias Ambry.Library.Root
  alias Ambry.Media.MediaTrack
  alias Ambry.Repo

  # Enough to cover a container header, its metadata and real audio frames at
  # both ends — see the moduledoc on why it is not larger.
  @window 1024 * 1024

  @doc """
  Indexes the library's files by size, for `holds?/2` to ask about.

  Takes the roots the caller already loaded, so this costs exactly one query
  and no per-track root lookups.
  """
  def index(roots) do
    by_id = Map.new(roots, &{&1.id, &1})

    MediaTrack
    |> select([t], {t.library_root_id, t.path, t.size})
    |> Repo.all()
    |> Enum.reduce(%{}, fn {root_id, path, size}, acc ->
      case absolute(by_id, root_id, path) do
        {:ok, absolute} -> Map.update(acc, size, [absolute], &[absolute | &1])
        :error -> acc
      end
    end)
  end

  @doc """
  Whether the library already holds this file's bytes under some other name.

  False for anything it cannot answer about — an unreadable file, a track
  whose own file has gone. "I couldn't tell" must never be actioned as "yes,
  already imported", because the cost of that answer is a release silently
  never being offered.
  """
  def holds?(index, path) do
    case File.stat(path) do
      {:ok, stat} -> index |> Map.get(stat.size, []) |> Enum.any?(&same_file?(&1, path, stat))
      {:error, _reason} -> false
    end
  end

  defp same_file?(library_path, path, stat) do
    case File.stat(library_path) do
      {:ok, %File.Stat{inode: inode, major_device: device}}
      when inode == stat.inode and device == stat.major_device ->
        true

      {:ok, _different_file} ->
        digest(library_path) == digest(path)

      {:error, _gone} ->
        false
    end
  end

  # `nil` on failure, and `nil != nil` is not how this compares: two
  # unreadable files must not read as the same file, so a failed digest is a
  # unique value rather than a shared one.
  defp digest(path) do
    case File.open(path, [:read, :binary, :raw]) do
      {:ok, io} ->
        try do
          :crypto.hash(:sha256, [read_at(io, 0), tail(io, path)])
        after
          File.close(io)
        end

      {:error, reason} ->
        {:unreadable, path, reason}
    end
  end

  defp tail(io, path) do
    case File.stat(path) do
      {:ok, %File.Stat{size: size}} when size > @window -> read_at(io, size - @window)
      _small_or_gone -> ""
    end
  end

  defp read_at(io, offset) do
    case :file.pread(io, offset, @window) do
      {:ok, bytes} -> bytes
      _eof_or_error -> ""
    end
  end

  defp absolute(_roots, nil, "/uploads/" <> _rest = web_path) do
    case Library.resolve(nil, web_path) do
      {:ok, absolute} -> {:ok, absolute}
      {:error, _reason} -> :error
    end
  end

  defp absolute(roots, root_id, path) do
    case roots do
      %{^root_id => %Root{} = root} ->
        case Library.resolve(root, path) do
          {:ok, absolute} -> {:ok, absolute}
          {:error, _reason} -> :error
        end

      _unknown_root ->
        :error
    end
  end
end
