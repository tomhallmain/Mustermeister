require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Myapp
  class Application < Rails::Application
    # Configure Sprockets cache to avoid file locking issues on Windows
    config.tmp_dir = ENV['RAILS_TMPDIR']
    config.paths['tmp'] = [ENV['RAILS_TMPDIR']]

    # Load the PostgreSQL checker before Rails initializes
    config.before_initialize do
      require_relative '../lib/postgres_connection_checker'
      PostgresConnectionChecker.check!
    end
    
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 7.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w(assets tasks))

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    # Use both Propshaft and Sprockets
    config.assets.enabled = true
    config.sass.load_paths << Rails.root.join('node_modules')

    # Enable Rack Attack for DDOS protection
    config.middleware.use Rack::Attack
  end
end
