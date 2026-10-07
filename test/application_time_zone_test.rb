require "test_helper"

class ApplicationTimeZoneTest < ActiveSupport::TestCase
  test "application time zone is Tokyo" do
    assert_equal "Tokyo", Rails.application.config.time_zone
    assert_equal "Tokyo", Time.zone.name
  end

  test "Date.current returns the current date just before midnight in Japan" do
    travel_to Time.utc(2026, 10, 7, 14, 59, 59) do
      assert_equal Date.new(2026, 10, 7), Date.current
    end
  end

  test "Date.current returns the next date at midnight in Japan" do
    travel_to Time.utc(2026, 10, 7, 15, 0, 0) do
      assert_equal Date.new(2026, 10, 8), Date.current
    end
  end
end
