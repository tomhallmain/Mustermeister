# Redis configuration
if Rails.env.production?
  redis_config = {
    url: ENV.fetch("REDIS_URL", "redis://localhost:6379/1"),
    ssl_params: { verify_mode: OpenSSL::SSL::VERIFY_NONE },
    timeout: 1,
    reconnect_attempts: 2
  }

  # Configure Redis for caching in production
  Rails.application.config.cache_store = :redis_cache_store, redis_config

  # Configure Redis for session storage in production
  Rails.application.config.session_store :redis_store,
    servers: [redis_config],
    expire_after: 90.minutes,
    key: "_#{Rails.application.class.module_parent_name}_session",
    threadsafe: true,
    secure: true

  # Configure Redis for Action Cable in production
  Rails.application.config.action_cable.cable = {
    "url" => redis_config[:url],
    "ssl_params" => redis_config[:ssl_params]
  }
else
  # Use file system for caching in development
  Rails.application.config.cache_store = :file_store, Rails.root.join('tmp', 'cache')

  # Use cookie store for sessions in development
  Rails.application.config.session_store :cookie_store,
    key: "_#{Rails.application.class.module_parent_name}_session",
    expire_after: 90.minutes,
    secure: Rails.env.production?

  # Configure Action Cable to use async adapter in development
  Rails.application.config.action_cable.cable = {
    "adapter" => "async"
  }
end

# Configure Active Job (using solid_queue which works with both Redis and file system)
Rails.application.config.active_job.queue_adapter = :solid_queue
Rails.application.config.solid_queue.connects_to = { database: { writing: :queue } } 