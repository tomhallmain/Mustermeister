# Auto-backup initializer
# Runs smart backup logic on application startup

Rails.application.config.after_initialize do
  # Run auto-backup based on environment and configuration
  should_run = case Rails.env
               when 'production'
                 true  # Always run in production
               when 'development'
                 true
                 # ENV['ENABLE_AUTO_BACKUP'] == 'true' || ENV['AUTO_BACKUP_DEV'] == 'true'
               else
                 ENV['ENABLE_AUTO_BACKUP'] == 'true'
               end
  
  if should_run
    begin
      puts "Running Rails auto-backup check..."
      result = BackupService.rails_auto_backup
      
      if result[:success]
        Rails.logger.info "Rails auto-backup completed: #{result[:reason]}"
        puts "✓ Rails auto-backup completed: #{result[:reason]}" if (Rails.env.development? || Rails.env.production?)
      elsif result[:skipped]
        Rails.logger.info "Rails auto-backup skipped: #{result[:reason]}"
        puts "⏭ Rails auto-backup skipped: #{result[:reason]}" if (Rails.env.development? || Rails.env.production?)
      else
        Rails.logger.error "Rails auto-backup failed: #{result[:error]}"
        puts "✗ Rails auto-backup failed: #{result[:error]}" if (Rails.env.development? || Rails.env.production?)
      end
    rescue => e
      Rails.logger.error "Rails auto-backup failed: #{e.message}"
      puts "Rails auto-backup failed: #{e.message}" if Rails.env.development?
    end
  end
end 
