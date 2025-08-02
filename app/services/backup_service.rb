# BackupService provides automated database backup functionality with three strategies:
#
# 1. **pg_dump method (default)**: Uses PostgreSQL's native pg_dump utility for fast,
#    reliable backups. Requires pg_dump to be installed and accessible in PATH.
#    This method creates compressed, binary-format backups that are optimized for
#    PostgreSQL restoration.
#
# 2. **Rails method**: Generates pure SQL export using ActiveRecord. This method
#    creates human-readable SQL files that can be restored to any PostgreSQL database.
#    No external dependencies required, but may be slower for large databases.
#
# 3. **both method**: Runs both pg_dump and Rails backups for maximum redundancy.
#    If pg_dump is unavailable or fails, the Rails method will still run.
#    Provides the best of both worlds - fast pg_dump backups plus reliable Rails fallback.
#
# Configuration is managed via config/backup_config.yml with sensible defaults.
# The service automatically determines backup intervals, manages retention,
# and validates database connectivity before attempting backups.
class BackupService
  CONFIG_FILE = "config/backup_config.yml"
  
  # Default configuration values
  DEFAULT_CONFIG = {
    'backup_method' => 'pg_dump',  # 'pg_dump', 'rails', or 'both'
    'backup_dir' => 'db_backups',
    'min_backup_interval_hours' => 6,
    'force_backup_interval_hours' => 24,
    'emergency_backup_interval_days' => 7,
    'keep_backup_count' => 5,
    'batch_size' => 1000,
  }.freeze
  
  # Load configuration
  def self.config
    @config ||= load_config
  end
  
  def self.load_config
    if File.exist?(CONFIG_FILE)
      YAML.load_file(CONFIG_FILE)
    else
      # Generate default config file
      generate_default_config
      DEFAULT_CONFIG
    end
  rescue => e
    Rails.logger.warn "Failed to load backup config: #{e.message}, using defaults"
    DEFAULT_CONFIG
  end
  
  def self.generate_default_config
    FileUtils.mkdir_p(File.dirname(CONFIG_FILE))
    File.write(CONFIG_FILE, DEFAULT_CONFIG.to_yaml)
    Rails.logger.info "Generated default backup config: #{CONFIG_FILE}"
  end
  
  # Configuration accessors
  def self.backup_dir
    config['backup_dir']&.gsub('\\', '/')
  end
  
  def self.db_name
    # Dynamically get database name from Rails configuration
    database_config = Rails.configuration.database_configuration[Rails.env]
    database_config['database']
  end
  
  def self.db_host
    database_config = Rails.configuration.database_configuration[Rails.env]
    database_config['host'] || 'localhost'
  end
  
  def self.db_port
    database_config = Rails.configuration.database_configuration[Rails.env]
    database_config['port'] || 5432
  end
  
  def self.db_username
    database_config = Rails.configuration.database_configuration[Rails.env]
    database_config['username']
  end
  
  def self.min_backup_interval
    config['min_backup_interval_hours'].hours
  end
  
  def self.force_backup_interval
    config['force_backup_interval_hours'].hours
  end
  
  def self.emergency_backup_interval
    config['emergency_backup_interval_days'].days
  end
  
  def self.keep_backup_count
    config['keep_backup_count']
  end
  
  def self.batch_size
    config['batch_size']
  end
  
  def self.backup_method
    config['backup_method'] || 'pg_dump'
  end
  
  def self.pg_dump_available?
    if Gem.win_platform?
      system("where pg_dump >nul 2>&1")
    else
      system("which pg_dump >/dev/null 2>&1")
    end
  end
  
  def self.pg_dump_version
    return nil unless pg_dump_available?
    
         if Gem.win_platform?
       # Use inline batch script to match backup script behavior
       batch_script = <<~BATCH
         @echo off
         pg_dump --version 2>&1
       BATCH
      
      # Write temporary batch file and execute it
      require 'tempfile'
      temp_file = Tempfile.new(['pg_dump_version', '.bat'])
      temp_file.write(batch_script)
      temp_file.close
      
      begin
        version_output = `"#{temp_file.path}" 2>&1`
        version_output.strip if $?.success?
      ensure
        temp_file.unlink
      end
    else
      # Use inline shell script to match backup script behavior
      shell_script = <<~SHELL
        #!/bin/bash
        pg_dump --version 2>&1
      SHELL
      
      # Write temporary shell script and execute it
      require 'tempfile'
      temp_file = Tempfile.new(['pg_dump_version', '.sh'])
      temp_file.write(shell_script)
      temp_file.close
      
      begin
        # Make executable and run
        File.chmod(0o755, temp_file.path)
        version_output = `"#{temp_file.path}" 2>&1`
        version_output.strip if $?.success?
      ensure
        temp_file.unlink
      end
    end
  rescue
    nil
  end
  
  def self.postgresql_server_version
    return nil unless defined?(ActiveRecord::Base)
    
    begin
      result = ActiveRecord::Base.connection.execute("SHOW server_version")
      result.first['server_version'] if result.any?
    rescue
      nil
    end
  end
  
  def self.version_compatibility_check
    pg_dump_ver = pg_dump_version
    server_ver = postgresql_server_version
    
    return {
      pg_dump_available: pg_dump_ver.present?,
      pg_dump_version: pg_dump_ver,
      server_version: server_ver,
      compatible: pg_dump_ver.present? && server_ver.present? && versions_compatible?(pg_dump_ver, server_ver),
      warnings: []
    }
  end
  
  def self.versions_compatible?(pg_dump_ver, server_ver)
    return false unless pg_dump_ver && server_ver
    
    # Extract major version numbers (e.g., "15.4" -> 15)
    pg_dump_major = pg_dump_ver.match(/(\d+)\./).to_a[1]&.to_i
    server_major = server_ver.match(/(\d+)\./).to_a[1]&.to_i
    
    return false unless pg_dump_major && server_major
    
    # pg_dump should be same major version or newer than server
    pg_dump_major >= server_major
  end
  
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
    
    # Unified auto-backup method that uses configured backup method
    def smart_auto_backup
      new.smart_auto_backup
    end
    
    # Both backup methods
    def both_auto_backup
      new.both_auto_backup
    end
    
    def both_backup
      new.both_backup
    end
  end
  
  def initialize
    @backup_dir = self.class.backup_dir
    @db_name = self.class.db_name
    @db_host = self.class.db_host
    @db_port = self.class.db_port
    @db_username = self.class.db_username
    
    # Validate that we can access the database configuration
    validate_database_config
    ensure_backup_directory_exists
  end
  
  def smart_auto_backup
    case self.class.backup_method
    when 'rails'
      rails_auto_backup
    when 'pg_dump', nil
      auto_backup
    when 'both'
      both_auto_backup
    else
      Rails.logger.warn "Unknown backup method '#{self.class.backup_method}', using pg_dump"
      auto_backup
    end
  end

  def auto_backup
    if should_backup?
      reason = backup_reason
      Rails.logger.info "Creating backup for database '#{@db_name}': #{reason}"
      backup
      { success: true, reason: reason }
    else
      reason = skip_reason
      Rails.logger.info "Skipping backup for database '#{@db_name}': #{reason}"
      { success: false, reason: reason, skipped: true }
    end
  end
  
  def backup
    # Test pg_dump availability and version compatibility
    compatibility = self.class.version_compatibility_check
    
    unless compatibility[:pg_dump_available]
      error_msg = <<~ERROR
        ⚠️  PGD_DUMP NOT AVAILABLE ⚠️
        
        The pg_dump executable is not found in your system PATH.
        This is required for the default backup method.
        
        🔧 SOLUTIONS:
        1. Install PostgreSQL client tools (recommended)
        2. Add PostgreSQL bin directory to your PATH
        3. Switch to Rails backup method by setting 'backup_method: rails' in config/backup_config.yml
        
        💡 The Rails backup method generates pure SQL and requires no external dependencies.
      ERROR
      
      Rails.logger.error error_msg
      return { success: false, error: error_msg }
    end
    
    # Check version compatibility
    unless compatibility[:compatible]
      error_msg = <<~ERROR
        ⚠️  VERSION COMPATIBILITY ISSUE ⚠️
        
        pg_dump version (#{compatibility[:pg_dump_version]}) may not be compatible 
        with PostgreSQL server version (#{compatibility[:server_version]}).
        
        🔧 SOLUTIONS:
        1. Update pg_dump to match or exceed server version (recommended)
        2. Switch to Rails backup method by setting 'backup_method: rails' in config/backup_config.yml
        
        💡 The Rails backup method generates pure SQL and requires no external dependencies.
      ERROR
      
      Rails.logger.error error_msg
      return { success: false, error: error_msg }
    end
    
    # Log version information
    Rails.logger.info "Using pg_dump: #{compatibility[:pg_dump_version]}"
    Rails.logger.info "PostgreSQL server: #{compatibility[:server_version]}"
    
    timestamp = Time.now.strftime("%Y%m%d_%H%M%S")
    backup_file = "#{@backup_dir}/#{@db_name}_#{timestamp}.sql"
    
    if Gem.win_platform?
      success = system("scripts\\backup_db.bat", @backup_dir)
    else
      success = system("scripts/backup_db.sh", @backup_dir)
    end
    
    if success
      cleanup_old_backups
      Rails.logger.info "Backup completed successfully for database '#{@db_name}': #{backup_file}"
      { success: true, file: backup_file }
    else
      Rails.logger.error "Backup failed for database '#{@db_name}'"
      { success: false, error: "Backup command failed" }
    end
  end
  
  def should_backup?
    return true if recent_backups.empty?
    
    time_since_last = time_since_last_backup
    
    time_since_last >= self.class.emergency_backup_interval ||
    time_since_last >= self.class.force_backup_interval ||
    time_since_last >= self.class.min_backup_interval
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
    
    if time_since_last >= self.class.emergency_backup_interval
      formatted_time = format_time_duration(time_since_last / 1.day * 24)
      "emergency backup (been #{formatted_time})"
    elsif time_since_last >= self.class.force_backup_interval
      formatted_time = format_time_duration(time_since_last / 1.hour)
      "force backup (been #{formatted_time})"
    elsif time_since_last >= self.class.min_backup_interval
      formatted_time = format_time_duration(time_since_last / 1.hour)
      "regular backup (been #{formatted_time})"
    else
      "unknown reason"
    end
  end
  
  def skip_reason
    time_since_last = time_since_last_backup
    formatted_time = format_time_duration(time_since_last / 1.hour)
    "only #{formatted_time} since last backup (minimum #{self.class.min_backup_interval / 1.hour} hours)"
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
  
  def cleanup_old_backups(keep_count = nil)
    keep_count ||= self.class.keep_backup_count
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
      Rails.logger.info "Creating Rails backup for database '#{@db_name}': #{reason}"
      result = rails_backup
      if result[:success]
        { success: true, reason: reason }
      else
        { success: false, error: result[:error] }
      end
    else
      reason = rails_skip_reason
      Rails.logger.info "Skipping Rails backup for database '#{@db_name}': #{reason}"
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
      Rails.logger.info "Rails backup completed successfully for database '#{@db_name}': #{backup_file}"
      { success: true, file: backup_file, size: File.size(backup_file) }
    rescue => e
      Rails.logger.error "Rails backup failed for database '#{@db_name}': #{e.message}"
      { success: false, error: e.message }
    end
  end
  
  def rails_should_backup?
    return true if rails_recent_backups.empty?
    
    time_since_last = rails_time_since_last_backup
    
    time_since_last >= self.class.emergency_backup_interval ||
    time_since_last >= self.class.force_backup_interval ||
    time_since_last >= self.class.min_backup_interval
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
    
    if time_since_last >= self.class.emergency_backup_interval
      formatted_time = format_time_duration(time_since_last / 1.day * 24)
      "emergency Rails backup (been #{formatted_time})"
    elsif time_since_last >= self.class.force_backup_interval
      formatted_time = format_time_duration(time_since_last / 1.hour)
      "force Rails backup (been #{formatted_time})"
    elsif time_since_last >= self.class.min_backup_interval
      formatted_time = format_time_duration(time_since_last / 1.hour)
      "regular Rails backup (been #{formatted_time})"
    else
      "unknown reason"
    end
  end
  
  def rails_skip_reason
    time_since_last = rails_time_since_last_backup
    formatted_time = format_time_duration(time_since_last / 1.hour)
    "only #{formatted_time} since last Rails backup (minimum #{self.class.min_backup_interval / 1.hour} hours)"
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
  
  def rails_cleanup_old_backups(keep_count = nil)
    keep_count ||= self.class.keep_backup_count
    return if rails_recent_backups.length <= keep_count
    
    to_delete = rails_recent_backups[keep_count..-1]
    to_delete.each do |backup|
      File.delete(backup)
      Rails.logger.info "Deleted old Rails backup: #{File.basename(backup)}"
    end
  end
  
  # ============================================================================
  # Both backup methods (pg_dump + Rails)
  # ============================================================================
  
  def both_auto_backup
    # Check if we should backup based on either method
    should_pg_dump = should_backup?
    should_rails = rails_should_backup?
    
    if should_pg_dump || should_rails
      reason = both_backup_reason(should_pg_dump, should_rails)
      Rails.logger.info "Creating both pg_dump and Rails backups for database '#{@db_name}': #{reason}"
      
      results = both_backup
      
      # Determine overall success
      pg_dump_success = results[:pg_dump][:success]
      rails_success = results[:rails][:success]
      
      if pg_dump_success && rails_success
        { success: true, reason: reason, results: results }
      elsif pg_dump_success || rails_success
        # At least one method succeeded
        successful_method = pg_dump_success ? 'pg_dump' : 'rails'
        { success: true, reason: "#{reason} (only #{successful_method} succeeded)", results: results }
      else
        # Both methods failed
        { success: false, error: "Both backup methods failed", results: results }
      end
    else
      reason = both_skip_reason
      Rails.logger.info "Skipping both backups for database '#{@db_name}': #{reason}"
      { success: false, reason: reason, skipped: true }
    end
  end
  
  def both_backup
    results = {}
    
    # Try pg_dump backup first
    begin
      compatibility = self.class.version_compatibility_check
      if compatibility[:pg_dump_available] && compatibility[:compatible]
        results[:pg_dump] = backup
      else
        results[:pg_dump] = { success: false, error: "pg_dump not available or incompatible" }
      end
    rescue => e
      results[:pg_dump] = { success: false, error: e.message }
    end
    
    # Always try Rails backup (no external dependencies)
    begin
      results[:rails] = rails_backup
    rescue => e
      results[:rails] = { success: false, error: e.message }
    end
    
    # Clean up old backups for both methods
    cleanup_old_backups
    rails_cleanup_old_backups
    
    results
  end
  
  def both_backup_reason(should_pg_dump, should_rails)
    if should_pg_dump && should_rails
      "both methods due (pg_dump: #{backup_reason}, Rails: #{rails_backup_reason})"
    elsif should_pg_dump
      "pg_dump due (#{backup_reason})"
    elsif should_rails
      "Rails due (#{rails_backup_reason})"
    else
      "unknown reason"
    end
  end
  
  def both_skip_reason
    pg_dump_time = time_since_last_backup
    rails_time = rails_time_since_last_backup
    
    pg_dump_formatted = format_time_duration(pg_dump_time / 1.hour)
    rails_formatted = format_time_duration(rails_time / 1.hour)
    
    "pg_dump: #{pg_dump_formatted} since last backup, Rails: #{rails_formatted} since last backup (minimum #{self.class.min_backup_interval / 1.hour} hours)"
  end
  
  private
  
  def recent_backups
    pattern = "#{@backup_dir}/#{@db_name}_*.sql"
    
    files = Dir.glob(pattern)
    filtered_files = files.reject { |f| f.include?('_rails_') }
    @recent_backups ||= filtered_files.sort_by { |f| File.mtime(f) }.reverse
  end
  
  def ensure_backup_directory_exists
    FileUtils.mkdir_p(@backup_dir)
  end
  
  def validate_database_config
    unless @db_name.present?
      raise "Database name is not configured. Please check your database.yml file."
    end
    
    begin
      # Test database connection
      ActiveRecord::Base.connection.execute("SELECT 1")
      Rails.logger.info "Database configuration validated successfully for '#{@db_name}'"
    rescue => e
      Rails.logger.error "Database configuration validation failed for '#{@db_name}': #{e.message}"
      raise "Database configuration is not valid for '#{@db_name}'. Please check your database.yml and environment variables."
    end
  end
  
  # Rails-specific private methods
  def rails_recent_backups
    pattern = "#{@backup_dir}/#{@db_name}_rails_*.sql"
    
    files = Dir.glob(pattern)
    @rails_recent_backups ||= files.sort_by { |f| File.mtime(f) }.reverse
  end
  
  def generate_rails_sql_dump
    sql_lines = []
    
    # Header
    sql_lines << "-- Rails-generated database backup"
    sql_lines << "-- Generated at: #{Time.current}"
    sql_lines << "-- Database: #{@db_name}"
    sql_lines << "-- Rails version: #{Rails.version}"
    sql_lines << ""
    
    # Get all tables in dependency order (respecting foreign key constraints)
    tables = get_tables_in_dependency_order
    
    tables.each do |table|
      sql_lines << generate_table_dump(table)
    end
    
    sql_lines.join("\n")
  end
  
  def get_tables_in_dependency_order
    all_tables = ActiveRecord::Base.connection.tables
    
    # Define the correct order based on foreign key dependencies
    # Tables with no dependencies come first, then tables that depend on them
    dependency_order = [
      'ar_internal_metadata',  # System table, no dependencies
      'schema_migrations',     # System table, no dependencies
      'users',                 # No foreign key dependencies
      'projects',              # Depends on users
      'statuses',              # Depends on projects
      'tags',                  # No foreign key dependencies
      'tasks',                 # Depends on projects, users, statuses
      'comments',              # Depends on projects, tasks, users
      'versions',              # No foreign keys but references other tables
      'tags_tasks'             # Junction table, depends on tags and tasks
    ]
    
    # Filter to only include tables that exist in the database
    existing_tables = dependency_order.select { |table| all_tables.include?(table) }
    
    # Add any remaining tables that weren't in our predefined order
    remaining_tables = all_tables - existing_tables
    existing_tables + remaining_tables.sort
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
    # Get table creation SQL using a more compatible approach
    begin
      # Get column information
      columns_result = ActiveRecord::Base.connection.execute(<<-SQL)
        SELECT 
          column_name,
          data_type,
          is_nullable,
          column_default,
          character_maximum_length,
          numeric_precision,
          numeric_scale
        FROM information_schema.columns 
        WHERE table_name = '#{table}' 
        ORDER BY ordinal_position
      SQL
      
      return "-- Could not generate structure for #{table}" if columns_result.count == 0
      
      # Build CREATE TABLE statement
      create_table_sql = "CREATE TABLE #{table} (\n"
      column_definitions = []
      
      columns_result.each do |col|
        column_def = "  #{col['column_name']} #{get_column_type(col)}"
        column_def += " NOT NULL" if col['is_nullable'] == 'NO'
        column_def += " DEFAULT #{col['column_default']}" if col['column_default'].present?
        column_definitions << column_def
      end
      
      create_table_sql += column_definitions.join(",\n")
      create_table_sql += "\n);"
      
      # Add primary key if exists
      pk_result = ActiveRecord::Base.connection.execute(<<-SQL)
        SELECT c.column_name
        FROM information_schema.table_constraints tc
        JOIN information_schema.constraint_column_usage AS ccu USING (constraint_schema, constraint_name)
        JOIN information_schema.columns AS c ON c.table_schema = tc.constraint_schema
          AND tc.table_name = c.table_name AND ccu.column_name = c.column_name
        WHERE constraint_type = 'PRIMARY KEY' AND tc.table_name = '#{table}'
      SQL
      
      if pk_result.count > 0
        pk_columns = pk_result.map { |row| row['column_name'] }
        create_table_sql += "\n\nALTER TABLE #{table} ADD CONSTRAINT #{table}_pkey PRIMARY KEY (#{pk_columns.join(', ')});"
      end
      
      # Add indexes
      indexes_result = ActiveRecord::Base.connection.execute(<<-SQL)
        SELECT 
          indexname,
          indexdef
        FROM pg_indexes 
        WHERE tablename = '#{table}' 
        AND indexname NOT LIKE '%_pkey'
        ORDER BY indexname
      SQL
      
      if indexes_result.count > 0
        create_table_sql += "\n"
        indexes_result.each do |index|
          create_table_sql += "\n#{index['indexdef']};"
        end
      end
      
      create_table_sql
     rescue => e
       Rails.logger.error "Failed to generate structure for #{table}: #{e.message}"
       raise e
     end
  end
  
  def get_column_type(column)
    case column['data_type']
    when 'character varying'
      if column['character_maximum_length']
        "varchar(#{column['character_maximum_length']})"
      else
        'varchar'
      end
    when 'character'
      if column['character_maximum_length']
        "char(#{column['character_maximum_length']})"
      else
        'char'
      end
    when 'numeric'
      if column['numeric_precision'] && column['numeric_scale']
        "numeric(#{column['numeric_precision']},#{column['numeric_scale']})"
      elsif column['numeric_precision']
        "numeric(#{column['numeric_precision']})"
      else
        'numeric'
      end
    when 'integer'
      'integer'
    when 'bigint'
      'bigint'
    when 'smallint'
      'smallint'
    when 'text'
      'text'
    when 'boolean'
      'boolean'
    when 'timestamp without time zone'
      'timestamp'
    when 'timestamp with time zone'
      'timestamptz'
    when 'date'
      'date'
    when 'time without time zone'
      'time'
    when 'time with time zone'
      'timetz'
    when 'json'
      'json'
    when 'jsonb'
      'jsonb'
    when 'uuid'
      'uuid'
    else
      column['data_type']
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
    batch_size = self.class.batch_size
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

  # Helper method to format time duration in a human-readable way
  def format_time_duration(hours)
    if hours < 1
      minutes = (hours * 60).round
      "#{minutes} minute#{minutes == 1 ? '' : 's'}"
    elsif hours < 24
      whole_hours = hours.floor
      remaining_minutes = ((hours - whole_hours) * 60).round
      if remaining_minutes == 0
        "#{whole_hours} hour#{whole_hours == 1 ? '' : 's'}"
      else
        "#{whole_hours} hour#{whole_hours == 1 ? '' : 's'} #{remaining_minutes} minute#{remaining_minutes == 1 ? '' : 's'}"
      end
    else
      days = (hours / 24).floor
      remaining_hours = (hours % 24).round
      if remaining_hours == 0
        "#{days} day#{days == 1 ? '' : 's'}"
      else
        "#{days} day#{days == 1 ? '' : 's'} #{remaining_hours} hour#{remaining_hours == 1 ? '' : 's'}"
      end
    end
  end
end 