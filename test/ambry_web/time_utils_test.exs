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
      assert "1 hour and 35 minutes" = TimeUtils.duration_display(5755)
      assert "1 hour and 1 minute" = TimeUtils.duration_display(3661)
      assert "1 minute" = TimeUtils.duration_display(60)
    end
  end
end
