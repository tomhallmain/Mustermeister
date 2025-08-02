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
      backup_method = BackupService.backup_method
      Rails.logger.info "Running #{backup_method} auto-backup check..."
      result = BackupService.smart_auto_backup # This will probably be a NOOP on test
      
      if result[:success]
        Rails.logger.info "#{backup_method} auto-backup completed: #{result[:reason]}"
      elsif result[:skipped]
        Rails.logger.info "#{backup_method} auto-backup skipped: #{result[:reason]}"
      else
        Rails.logger.error "#{backup_method} auto-backup failed: #{result[:error]}"
      end
    rescue => e
      Rails.logger.error "Auto-backup failed: #{e.message}"
    end
  end
end 
