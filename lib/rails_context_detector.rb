module RailsContextDetector
  def self.server_starting?
    # Check if this is a server startup context
    defined?(Rails::Server) && Rails.const_defined?(:Server) ||
    defined?(Rails::Console) && Rails.const_defined?(:Console) ||
    defined?(Rails::Application) && Rails.application.class.name.include?('Server')
  end

  def self.rake_task?
    # Check if this is a rake task context
    defined?(Rake) && defined?(Rake.application) && Rake.application.top_level_tasks.any?
  end

  def self.console?
    # Check if this is a Rails console context
    defined?(Rails::Console) && Rails.const_defined?(:Console)
  end

  def self.test_environment?
    # Check if we're in test environment
    Rails.env.test?
  end

  def self.should_run_startup_checks?
    # Determine if startup checks should run
    return false if test_environment?
    return false if rake_task?
    return true if console?
    return true if server_starting?
    
    # Default to true for other contexts (like web requests)
    true
  end

  def self.should_run_auto_backup?
    # Determine if auto-backup should run
    return false if test_environment?
    return false if rake_task?
    return false if console? # Usually don't want backups during console sessions
    return true if server_starting?
    
    # Check environment variables
    case Rails.env
    when 'production'
      true
    when 'development'
      true
      # ENV['ENABLE_AUTO_BACKUP'] == 'true' || ENV['AUTO_BACKUP_DEV'] == 'true'
    else
      ENV['ENABLE_AUTO_BACKUP'] == 'true'
    end
  end

  def self.current_context
    contexts = []
    contexts << 'server' if server_starting?
    contexts << 'rake' if rake_task?
    contexts << 'console' if console?
    contexts << 'test' if test_environment?
    contexts << 'production' if Rails.env.production?
    contexts << 'development' if Rails.env.development?
    
    contexts.empty? ? 'unknown' : contexts.join('+')
  end
end
