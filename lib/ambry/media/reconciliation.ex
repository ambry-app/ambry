defmodule Ambry.Media.Reconciliation do
  @moduledoc """
  Noticing that a recording's files stopped being there.

  Files go missing for ordinary reasons and none of them mean the recording
  should be deleted, so this only ever *records* what it found: `missing_since`
  is stamped when the files cannot be read and cleared when they come back.
  Nothing cascades.

  **What counts as missing** is the files a recording needs in order to play:
  its tracks for direct play, its transcoded outputs otherwise. Source files
  that only fed a transcode are deliberately not checked, since a recording
  whose originals were cleaned up still plays perfectly.

  **Unreadable is not missing.** A path that exists but cannot be read is
  reported as an error: the two need different fixes, and conflating them
  sends the operator looking for a file that was there all along.
  """

  import Ecto.Query

  alias Ambry.Media.Media
  alias Ambry.Media.MediaTrack
  alias Ambry.Paths
  alias Ambry.Repo

  @doc """
  Checks every recording and records what is missing.

  Returns `{:ok, %{checked: n, missing: n, healed: n}}`. `healed` is why this
  is a sweep rather than a one-way flag.
  """
  def reconcile_all do
    Media
    |> preload(:media_tracks)
    |> Repo.all()
    |> Enum.reduce(%{checked: 0, missing: 0, healed: 0}, fn media, counts ->
      counts = Map.update!(counts, :checked, &(&1 + 1))

      case reconcile(media) do
        {:ok, :missing} -> Map.update!(counts, :missing, &(&1 + 1))
        {:ok, :healed} -> Map.update!(counts, :healed, &(&1 + 1))
        {:ok, :unchanged} -> counts
      end
    end)
    |> then(&{:ok, &1})
  end

  @doc """
  Checks one recording and records the result.

  Returns `{:ok, :missing | :healed | :unchanged}`.
  """
  def reconcile(%Media{} = media) do
    case {missing_files(media), media.missing_since} do
      {[], nil} -> {:ok, :unchanged}
      {[], _was_missing} -> heal(media)
      {[_ | _], nil} -> mark_missing(media)
      {[_ | _], _already} -> {:ok, :unchanged}
    end
  end

  @doc """
  The files a recording needs but cannot read.

  A recording with no playable files at all has nothing to be missing, so it
  is not reported.
  """
  def missing_files(%Media{} = media) do
    media
    |> playable_files()
    |> Enum.reject(&File.regular?/1)
  end

  @doc """
  The files a recording is served from, as absolute disk paths.
  """
  def playable_files(%Media{media_tracks: tracks} = media) when is_list(tracks) do
    case Enum.map(tracks, &MediaTrack.disk_path/1) do
      [] -> legacy_outputs(media)
      # A stored path that cannot resolve cannot be served either. Raising
      # keeps the broken invariant loud rather than one more missing file.
      resolved -> Enum.map(resolved, fn {:ok, path} -> path end)
    end
  end

  def playable_files(%Media{} = media), do: legacy_outputs(media)

  defp legacy_outputs(%Media{} = media) do
    [media.mp4_path, media.hls_path, media.mpd_path]
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&Paths.web_to_disk/1)
  end

  defp mark_missing(media) do
    with {:ok, _media} <- put_missing_since(media, DateTime.utc_now(:second)),
         do: {:ok, :missing}
  end

  defp heal(media) do
    with {:ok, _media} <- put_missing_since(media, nil), do: {:ok, :healed}
  end

  # Straight through rather than via `Media.update_media/3`: a bookkeeping
  # note about the filesystem must not touch provenance, reindex search, or
  # broadcast to every connected client on a nightly sweep.
  defp put_missing_since(media, missing_since) do
    media
    |> Ecto.Changeset.change(%{missing_since: missing_since})
    |> Repo.update()
  end
end
