require "test_helper"
require "brakeman"

# Runs the same static security scan as bin/brakeman, so a new warning fails
# the regular test run. Warnings listed in config/brakeman.ignore (if one is
# added) are excluded, as they are for the CLI. The CLI's --ensure-latest
# gem-version check is not repeated here, since it needs network access.
class BrakemanTest < ActiveSupport::TestCase
  test "brakeman reports no security warnings or scan errors" do
    tracker = Brakeman.run(app_path: Rails.root.to_s, quiet: true, report_progress: false)

    # assert rather than assert_empty: the latter appends an inspect dump of
    # every Warning object after the readable list.
    warnings = tracker.filtered_warnings
    assert warnings.empty?, "Brakeman warnings:\n\n#{warnings.map(&:to_s).join("\n\n")}"
    assert tracker.errors.empty?, "Brakeman scan errors:\n\n#{tracker.errors.map { |e| e[:error] }.join("\n")}"
  end
end
