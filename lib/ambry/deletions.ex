defmodule Ambry.Deletions do
  @moduledoc """
  Track deletions of top-level records, like people, books, series, and media.

  The purpose is to be able to notify clients that later ask for what has
  changed since the last time they checked in.
  """

  use Boundary,
    deps: [Ambry],
    exports: [
      Deletion
    ]
end
