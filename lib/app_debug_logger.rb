# Gate for this app's own intentional Rails.logger.debug tracing (request
# param dumps, LLM prompt/response dumps, etc.), independent of Rails'
# framework-wide config.log_level. Flipping config.log_level to :debug to see
# these also reactivates framework-level debug noise (SQL, ActionView partial
# renders, job enqueues, ...) - this lets that stay off while still being able
# to switch the app's own debug traces on with a single env var.
#
# Off by default. To enable: APP_DEBUG_LOGGING=true (any of the standard
# truthy strings below also work).
module AppDebugLogger
  TRUTHY_VALUES = %w[1 true yes on].freeze

  def self.enabled?
    TRUTHY_VALUES.include?(ENV["APP_DEBUG_LOGGING"].to_s.strip.downcase)
  end

  # Accepts a plain message or a block (like Ruby's own Logger#debug) - use the
  # block form when building the message does real work (extra queries,
  # heavy interpolation), so that work is skipped entirely when disabled.
  def self.debug(message = nil, &block)
    return unless enabled?

    block_given? ? Rails.logger.debug(&block) : Rails.logger.debug(message)
  end
end
