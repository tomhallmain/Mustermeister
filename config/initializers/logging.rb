require 'logging'
require 'fileutils'

# Note: The logging gem may show a syslog deprecation warning on Windows
# This is a known issue with the logging gem and will be resolved when
# the gem updates its gemspec to include syslog as a dependency

# Determine platform-specific log directory
log_dir = if Gem.win_platform?
  # Windows: AppData/Local/Mustermeister/logs
  File.join(ENV['LOCALAPPDATA'], 'Mustermeister', 'logs')
else
  # Unix-based: ~/Mustermeister/logs
  File.join(Dir.home, 'Mustermeister', 'logs')
end

# Create logs directory if it doesn't exist
FileUtils.mkdir_p(log_dir)

# Configure the logging system
Logging.init

# Create a layout for the log messages
layout = Logging.layouts.pattern(
  pattern: '[%d] %-5l: %m\n',
  date_pattern: '%Y-%m-%d %H:%M:%S'
)

# Create the appender for the log file
appender = Logging.appenders.rolling_file(
  'rails.log',
  filename: File.join(log_dir, "#{Rails.env}.log"),  # Platform-specific path
  layout: layout,
  keep: 2,  # Keep 2 log files
  age: 'daily',
  truncate: true,
  safe: true  # Helps with Windows file locking issues
)

# Create console appender for STDOUT
console_appender = Logging.appenders.stdout(
  'console',
  layout: layout
)

# Create the logger
logger = Logging.logger['Rails']
logger.add_appenders(appender, console_appender)  # Add both file and console appenders

# Set the log level based on environment
logger.level = if Rails.env.production?
  :info
elsif Rails.env.development?
  :debug
else
  :warn
end

# Configure Rails to use our logger directly
Rails.logger = logger

# Define dummy broadcast_to method to satisfy Rails 8
class << Rails.logger
  def broadcast_to(_console)
    # No-op since we're handling output through logging gem
  end
end

# Log unhandled exceptions
Rails.application.config.exceptions_app = ->(env) do
  request = ActionDispatch::Request.new(env)
  Rails.logger.error("Unhandled exception: #{request.path}")
  Rails.logger.error(env['action_dispatch.exception'].inspect)
  Rails.logger.error(env['action_dispatch.exception'].backtrace.join("\n"))
  ActionDispatch::PublicExceptions.new(Rails.public_path).call(env)
end