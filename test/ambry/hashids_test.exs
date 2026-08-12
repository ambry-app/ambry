defmodule Ambry.HashidsTest do
  @moduledoc """
  A tripwire, not a unit test.

  `Ambry.Hashids` is `Hashids.new([])` — no salt, library defaults — and two
  things now depend on that encoding being stable forever:

    * every track's URL (`Ambry.Media.MediaTrack.web_path/1`), which is
      merely cosmetic to change; and
    * **every filename in every managed library**
      (`Ambry.Media.Media.filename_token/1`), which is not.

  Giving the coder a salt or a `min_length` — an entirely reasonable thing to
  want for the URL side — would rename the operator's whole library on the
  next organize run. That has to be a decision somebody makes on purpose, so
  this test fails first and says why.
  """
  use ExUnit.Case, async: true

  alias Ambry.Hashids

  test "the encoding is stable" do
    assert Hashids.encode(1) == "jR"
    assert Hashids.encode(104) == "mw0"
    assert Hashids.encode(99_999) == "wprD1"
  end

  test "round-trips" do
    assert {:ok, [104]} = Hashids.decode(Hashids.encode(104))
  end
end
