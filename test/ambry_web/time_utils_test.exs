defmodule AmbryWeb.TimeUtilsTest do
  use ExUnit.Case

  alias AmbryWeb.TimeUtils

  describe "format_timecode/1" do
    test "handles nil" do
      assert nil == TimeUtils.format_timecode(nil)
    end

    test "without hours" do
      assert "35:55" = TimeUtils.format_timecode(2155)
    end

    test "with hours" do
      assert "1:35:55" = TimeUtils.format_timecode(5755)
    end
  end

  describe "duration_display/1" do
    test "handles nil" do
      assert nil == TimeUtils.duration_display(nil)
    end

    test "without hours" do
      assert "35 minutes" = TimeUtils.duration_display(2155)
    end

    test "with hours" do
      assert "1 hours and 35 minutes" = TimeUtils.duration_display(5755)
    end
  end
end
