# Auto-backup initializer
# Runs smart backup logic on application startup

Rails.application.config.after_initialize do
  # Run auto-backup based on environment and configuration
  should_run = case Rails.env
               when 'production'
                 true  # Always run in production
               when 'development'
                 ENV['ENABLE_AUTO_BACKUP'] == 'true' || ENV['AUTO_BACKUP_DEV'] == 'true'
               else
                 ENV['ENABLE_AUTO_BACKUP'] == 'true'
               end
  
  if should_run
    begin
      puts "Running auto-backup check..."
      result = BackupService.auto_backup
      
      if result[:success]
        Rails.logger.info "Auto-backup completed: #{result[:reason]}"
        puts "✓ Auto-backup completed: #{result[:reason]}" if Rails.env.development?
      elsif result[:skipped]
        Rails.logger.info "Auto-backup skipped: #{result[:reason]}"
        puts "⏭ Auto-backup skipped: #{result[:reason]}" if Rails.env.development?
      else
        Rails.logger.error "Auto-backup failed: #{result[:error]}"
        puts "✗ Auto-backup failed: #{result[:error]}" if Rails.env.development?
      end
    rescue => e
      Rails.logger.error "Auto-backup failed: #{e.message}"
      puts "Auto-backup failed: #{e.message}" if Rails.env.development?
    end
  end
end 