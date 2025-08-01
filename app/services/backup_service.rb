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
    
    # Rails-based backup methods (separate from pg_dump logic)
    def rails_backup
      new.rails_backup
    end
    
    def rails_auto_backup
      new.rails_auto_backup
    end
    
    def rails_should_backup?
      new.rails_should_backup?
    end
    
    def rails_last_backup_time
      new.rails_last_backup_time
    end
    
    def rails_time_since_last_backup
      new.rails_time_since_last_backup
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
  
  # ============================================================================
  # Rails-based backup methods (completely separate from pg_dump logic)
  # ============================================================================
  
  def rails_auto_backup
    if rails_should_backup?
      reason = rails_backup_reason
      Rails.logger.info "Creating Rails backup: #{reason}"
      rails_backup
      { success: true, reason: reason }
    else
      reason = rails_skip_reason
      Rails.logger.info "Skipping Rails backup: #{reason}"
      { success: false, reason: reason, skipped: true }
    end
  end
  
  def rails_backup
    timestamp = Time.now.strftime("%Y%m%d_%H%M%S")
    backup_file = "#{@backup_dir}/#{@db_name}_rails_#{timestamp}.sql"
    
    begin
      sql_content = generate_rails_sql_dump
      File.write(backup_file, sql_content)
      
      rails_cleanup_old_backups
      Rails.logger.info "Rails backup completed successfully: #{backup_file}"
      { success: true, file: backup_file, size: File.size(backup_file) }
    rescue => e
      Rails.logger.error "Rails backup failed: #{e.message}"
      { success: false, error: e.message }
    end
  end
  
  def rails_should_backup?
    return true if rails_recent_backups.empty?
    
    time_since_last = rails_time_since_last_backup
    
    time_since_last >= EMERGENCY_BACKUP_INTERVAL ||
    time_since_last >= FORCE_BACKUP_INTERVAL ||
    time_since_last >= MIN_BACKUP_INTERVAL
  end
  
  def rails_last_backup_time
    return nil if rails_recent_backups.empty?
    File.mtime(rails_recent_backups.first)
  end
  
  def rails_time_since_last_backup
    return Float::INFINITY if rails_last_backup_time.nil?
    Time.now - rails_last_backup_time
  end
  
  def rails_backup_reason
    time_since_last = rails_time_since_last_backup
    
    if time_since_last >= EMERGENCY_BACKUP_INTERVAL
      "emergency Rails backup (been #{time_since_last / 1.day} days)"
    elsif time_since_last >= FORCE_BACKUP_INTERVAL
      "force Rails backup (been #{time_since_last / 1.hour} hours)"
    elsif time_since_last >= MIN_BACKUP_INTERVAL
      "regular Rails backup (been #{time_since_last / 1.hour} hours)"
    else
      "unknown reason"
    end
  end
  
  def rails_skip_reason
    time_since_last = rails_time_since_last_backup
    "only #{time_since_last / 1.hour} hours since last Rails backup (minimum #{MIN_BACKUP_INTERVAL / 1.hour} hours)"
  end
  
  def rails_list_backups
    rails_recent_backups.map do |backup|
      {
        filename: File.basename(backup),
        size: File.size(backup),
        created_at: File.mtime(backup),
        path: backup,
        type: 'rails'
      }
    end
  end
  
  def rails_cleanup_old_backups(keep_count = 5)
    return if rails_recent_backups.length <= keep_count
    
    to_delete = rails_recent_backups[keep_count..-1]
    to_delete.each do |backup|
      File.delete(backup)
      Rails.logger.info "Deleted old Rails backup: #{File.basename(backup)}"
    end
  end
  
  private
  
  def recent_backups
    @recent_backups ||= Dir.glob("#{@backup_dir}/#{@db_name}_*.sql")
                          .reject { |f| f.include?('_rails_') }  # Exclude Rails backups
                          .sort_by { |f| File.mtime(f) }
                          .reverse
  end
  
  def ensure_backup_directory_exists
    Dir.mkdir(@backup_dir) unless Dir.exist?(@backup_dir)
  end
  
  # Rails-specific private methods
  def rails_recent_backups
    @rails_recent_backups ||= Dir.glob("#{@backup_dir}/#{@db_name}_rails_*.sql")
                                 .sort_by { |f| File.mtime(f) }
                                 .reverse
  end
  
  def generate_rails_sql_dump
    sql_lines = []
    
    # Header
    sql_lines << "-- Rails-generated database backup"
    sql_lines << "-- Generated at: #{Time.current}"
    sql_lines << "-- Database: #{@db_name}"
    sql_lines << "-- Rails version: #{Rails.version}"
    sql_lines << ""
    
    # Get all tables
    tables = ActiveRecord::Base.connection.tables.sort
    
    tables.each do |table|
      sql_lines << generate_table_dump(table)
    end
    
    sql_lines.join("\n")
  end
  
  def generate_table_dump(table)
    lines = []
    
    # Table structure
    lines << "-- Table structure for #{table}"
    lines << generate_table_structure(table)
    lines << ""
    
    # Table data
    lines << "-- Table data for #{table}"
    lines << generate_table_data(table)
    lines << ""
    
    lines.join("\n")
  end
  
  def generate_table_structure(table)
    # Get table creation SQL
    result = ActiveRecord::Base.connection.execute("SELECT pg_get_tabledef('#{table}'::regclass)")
    if result.any?
      result.first['pg_get_tabledef']
    else
      "-- Could not generate structure for #{table}"
    end
  end
  
  def generate_table_data(table)
    # Get row count
    count_result = ActiveRecord::Base.connection.execute("SELECT COUNT(*) as count FROM #{table}")
    row_count = count_result.first['count'].to_i
    
    if row_count == 0
      return "-- Table #{table} is empty"
    end
    
    # Get column information
    columns_result = ActiveRecord::Base.connection.execute(<<-SQL)
      SELECT column_name, data_type 
      FROM information_schema.columns 
      WHERE table_name = '#{table}' 
      ORDER BY ordinal_position
    SQL
    
    columns = columns_result.map { |row| row['column_name'] }
    
    # Get data in batches to avoid memory issues
    batch_size = 1000
    offset = 0
    data_lines = []
    
    while offset < row_count
      data_result = ActiveRecord::Base.connection.execute(<<-SQL)
        SELECT * FROM #{table} 
        ORDER BY #{columns.first} 
        LIMIT #{batch_size} OFFSET #{offset}
      SQL
      
      data_result.each do |row|
        values = columns.map do |col|
          value = row[col]
          if value.nil?
            'NULL'
          elsif value.is_a?(String)
            "'#{value.gsub("'", "''")}'"
          else
            value.to_s
          end
        end
        
        data_lines << "INSERT INTO #{table} (#{columns.join(', ')}) VALUES (#{values.join(', ')});"
      end
      
      offset += batch_size
    end
    
    data_lines.join("\n")
  end
end 