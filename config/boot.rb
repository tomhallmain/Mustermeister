ENV.delete('TMPDIR')  # Clear any existing value
ENV['TMP'] = ENV['RAILS_TMPDIR'] = 'C:/rails_temp'
ENV['TEMP'] = ENV['RAILS_TMPDIR']
ENV["BUNDLE_GEMFILE"] ||= File.expand_path("../Gemfile", __dir__)

require "bundler/setup" # Set up gems listed in the Gemfile.
require "bootsnap/setup" # Speed up boot time by caching expensive operations.
