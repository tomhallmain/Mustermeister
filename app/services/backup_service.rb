class BackupService
  BACKUP_DIR = "db_backups"
  DB_NAME = "myapp_development"
  
  # Minimum time between backups (6 hours)
  MIN_BACKUP_INTERVAL = 6.hours
  
  # Force backup after this time (24 hours)
  FORCE_BACKUP_INTERVAL = 24.hours
  
  # Emergency backup after this time (7 days)
  EMERGENCY_BACKUP_INTERVAL = 7.days
  
  class << self
    def auto_backup
      new.auto_backup
    end
    
    def backup
      new.backup
    end
    
    def should_backup?
      new.should_backup?
    end
    
    def last_backup_time
      new.last_backup_time
    end
    
    def time_since_last_backup
      new.time_since_last_backup
    end
  end
  
  def initialize
    @backup_dir = BACKUP_DIR
    @db_name = DB_NAME
    ensure_backup_directory_exists
  end
  
  def auto_backup
    if should_backup?
      reason = backup_reason
      Rails.logger.info "Creating backup: #{reason}"
      backup
      { success: true, reason: reason }
    else
      reason = skip_reason
      Rails.logger.info "Skipping backup: #{reason}"
      { success: false, reason: reason, skipped: true }
    end
  end
  
  def backup
    timestamp = Time.now.strftime("%Y%m%d_%H%M%S")
    backup_file = "#{@backup_dir}/#{@db_name}_#{timestamp}.sql"
    
    if Gem.win_platform?
      success = system("scripts\\backup_db.bat")
    else
      success = system("scripts/backup_db.sh")
    end
    
    if success
      cleanup_old_backups
      Rails.logger.info "Backup completed successfully: #{backup_file}"
      { success: true, file: backup_file }
    else
      Rails.logger.error "Backup failed"
      { success: false, error: "Backup command failed" }
    end
  end
  
  def should_backup?
    return true if recent_backups.empty?
    
    time_since_last = time_since_last_backup
    
    time_since_last >= EMERGENCY_BACKUP_INTERVAL ||
    time_since_last >= FORCE_BACKUP_INTERVAL ||
    time_since_last >= MIN_BACKUP_INTERVAL
  end
  
  def last_backup_time
    return nil if recent_backups.empty?
    File.mtime(recent_backups.first)
  end
  
  def time_since_last_backup
    return Float::INFINITY if last_backup_time.nil?
    Time.now - last_backup_time
  end
  
  def backup_reason
    time_since_last = time_since_last_backup
    
    if time_since_last >= EMERGENCY_BACKUP_INTERVAL
      "emergency backup (been #{time_since_last / 1.day} days)"
    elsif time_since_last >= FORCE_BACKUP_INTERVAL
      "force backup (been #{time_since_last / 1.hour} hours)"
    elsif time_since_last >= MIN_BACKUP_INTERVAL
      "regular backup (been #{time_since_last / 1.hour} hours)"
    else
      "unknown reason"
    end
  end
  
  def skip_reason
    time_since_last = time_since_last_backup
    "only #{time_since_last / 1.hour} hours since last backup (minimum #{MIN_BACKUP_INTERVAL / 1.hour} hours)"
  end
  
  def list_backups
    recent_backups.map do |backup|
      {
        filename: File.basename(backup),
        size: File.size(backup),
        created_at: File.mtime(backup),
        path: backup
      }
    end
  end
  
  def cleanup_old_backups(keep_count = 5)
    return if recent_backups.length <= keep_count
    
    to_delete = recent_backups[keep_count..-1]
    to_delete.each do |backup|
      File.delete(backup)
      Rails.logger.info "Deleted old backup: #{File.basename(backup)}"
    end
  end
  
  private
  
  def recent_backups
    @recent_backups ||= Dir.glob("#{@backup_dir}/#{@db_name}_*.sql")
                          .sort_by { |f| File.mtime(f) }
                          .reverse
  end
  
  def ensure_backup_directory_exists
    Dir.mkdir(@backup_dir) unless Dir.exist?(@backup_dir)
  end
end 