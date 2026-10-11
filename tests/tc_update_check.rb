# frozen_string_literal: true

# Run (no SketchUp needed): ruby tests/tc_update_check.rb
require 'minitest/autorun'
require_relative 'stub_sketchup'
require_relative '../skp_cm_extensions_hub/update_check'

class TestUpdateCheck < Minitest::Test
  U = SkpCm::ExtensionsHub::UpdateCheck
  DAY = 24 * 60 * 60

  def test_check_due
    now = 1_000_000_000
    assert U.check_due?(0, now), 'never checked'
    assert U.check_due?(nil, now), 'missing preference'
    assert U.check_due?(now - DAY, now)
    refute U.check_due?(now - DAY + 60, now)
    assert U.check_due?(now + DAY, now), 'clock moved backwards → check again'
  end

  def test_update_notice
    entries = [
      { 'name' => 'A', 'status' => 'update_available', 'latest_version' => '1.1.0', 'pending_restart' => false },
      { 'name' => 'B', 'status' => 'up_to_date', 'latest_version' => '2.0.0' },
      { 'name' => 'C', 'status' => 'update_available', 'latest_version' => '3.0.1' }
    ]
    assert_equal 'มีอัปเดต 2 รายการ: A 1.1.0, C 3.0.1', U.update_notice(entries)
  end

  def test_no_update_notice
    assert_nil U.update_notice([{ 'name' => 'B', 'status' => 'up_to_date' }])
    assert_nil U.update_notice([])
  end
end
