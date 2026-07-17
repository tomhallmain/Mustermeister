require "test_helper"

class AppDebugLoggerTest < ActiveSupport::TestCase
  # A minimal stand-in for Rails.logger. Swapping Rails.logger itself (rather
  # than stubbing #debug on the real one) sidesteps minitest's Object#stub,
  # which forwards a passed block as a positional arg rather than yielding it -
  # awkward to match against a `&block`-taking double.
  class FakeLogger
    attr_reader :messages

    def initialize
      @messages = []
    end

    def debug(message = nil)
      @messages << (block_given? ? yield : message)
    end
  end

  def setup
    @original_env = ENV["APP_DEBUG_LOGGING"]
    @original_logger = Rails.logger
    Rails.logger = FakeLogger.new
  end

  def teardown
    ENV["APP_DEBUG_LOGGING"] = @original_env
    Rails.logger = @original_logger
  end

  test "enabled? is false by default" do
    ENV.delete("APP_DEBUG_LOGGING")
    assert_not AppDebugLogger.enabled?
  end

  test "enabled? recognizes common truthy values" do
    %w[1 true TRUE yes on].each do |value|
      ENV["APP_DEBUG_LOGGING"] = value
      assert AppDebugLogger.enabled?, "Expected #{value.inspect} to be treated as enabled"
    end
  end

  test "enabled? treats other values as disabled" do
    %w[0 false no off garbage].each do |value|
      ENV["APP_DEBUG_LOGGING"] = value
      assert_not AppDebugLogger.enabled?, "Expected #{value.inspect} to be treated as disabled"
    end
  end

  test "debug does not log a plain message when disabled" do
    ENV["APP_DEBUG_LOGGING"] = "false"
    AppDebugLogger.debug("should not log")
    assert_empty Rails.logger.messages
  end

  test "debug logs a plain message when enabled" do
    ENV["APP_DEBUG_LOGGING"] = "true"
    AppDebugLogger.debug("hello")
    assert_equal ["hello"], Rails.logger.messages
  end

  test "debug does not evaluate a block when disabled" do
    ENV["APP_DEBUG_LOGGING"] = "false"
    block_called = false

    AppDebugLogger.debug { block_called = true; "expensive" }

    assert_not block_called, "Block should not be evaluated when debug logging is disabled"
    assert_empty Rails.logger.messages
  end

  test "debug evaluates and logs a block when enabled" do
    ENV["APP_DEBUG_LOGGING"] = "true"
    AppDebugLogger.debug { "lazy message" }
    assert_equal ["lazy message"], Rails.logger.messages
  end
end
