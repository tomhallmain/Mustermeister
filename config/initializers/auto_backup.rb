# Auto-backup initializer
# Runs smart backup logic on application startup (only when appropriate)

Rails.application.config.after_initialize do
  require_relative '../../lib/rails_context_detector'
  
  if RailsContextDetector.should_run_auto_backup?
    Rails.logger.info "Running auto-backup check (context: #{RailsContextDetector.current_context})"
    
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
  # else
  #   Rails.logger.debug "Skipping auto-backup (context: #{RailsContextDetector.current_context})"
  end
end 
