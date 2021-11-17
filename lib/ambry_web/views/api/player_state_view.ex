defmodule AmbryWeb.API.PlayerStateView do
  use AmbryWeb, :view

  alias AmbryWeb.API.{BookView, ChapterView, PlayerStateView}

  def render("index.json", %{player_states: player_states, has_more?: has_more?}) do
    %{
      data: render_many(player_states, PlayerStateView, "player_state.json"),
      hasMore: has_more?
    }
  end

  def render("show.json", %{player_state: player_state}) do
    %{data: render_one(player_state, PlayerStateView, "player_state.json")}
  end

  def render("player_state.json", %{player_state: player_state}) do
    duration = Decimal.to_float(player_state.media.duration)

    %{
      id: player_state.media.id,
      playbackRate: Decimal.to_float(player_state.playback_rate),
      position: Decimal.to_float(player_state.position),
      media: %{
        id: player_state.media.id,
        abridged: player_state.media.abridged,
        fullCast: player_state.media.full_cast,
        mpdPath: player_state.media.mpd_path,
        hlsPath: player_state.media.hls_path,
        duration: duration,
        narrators: narrators(player_state.media.narrators),
        book: render_one(player_state.media.book, BookView, "book_index.json"),
        chapters: ChapterView.chapters(player_state.media.chapters, duration)
      }
    }
  end

  defp narrators(narrators) do
    Enum.map(narrators, fn narrator ->
      %{
        personId: narrator.person_id,
        name: narrator.name
      }
    end)
  end
end
