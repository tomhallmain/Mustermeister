namespace :db do
  desc "Backup the database"
  task backup: :environment do
    result = BackupService.backup
    
    if result[:success]
      puts "✓ Backup completed successfully: #{result[:file]}"
    else
      puts "✗ Backup failed: #{result[:error]}"
      exit 1
    end
  end

  desc "Restore the database from a backup"
  task :restore, [:backup_file] => :environment do |t, args|
    if args[:backup_file].nil?
      puts "Please specify a backup file: rake db:restore[path/to/backup.sql]"
      exit 1
    end
    
    backup_file = args[:backup_file]
    
    unless File.exist?(backup_file)
      puts "✗ Backup file not found: #{backup_file}"
      exit 1
    end
    
    if Gem.win_platform?
      success = system("scripts\\restore_db.bat #{backup_file}")
    else
      success = system("scripts/restore_db.sh #{backup_file}")
    end
    
    if success
      puts "✓ Database restored successfully from #{backup_file}"
    else
      puts "✗ Database restore failed"
      exit 1
    end
  end

  desc "Auto backup with smart timing logic"
  task auto_backup: :environment do
    result = BackupService.auto_backup
    
    if result[:success]
      puts "✓ Backup created: #{result[:reason]}"
    elsif result[:skipped]
      puts "⏭ Skipped backup: #{result[:reason]}"
    else
      puts "✗ Backup failed: #{result[:error]}"
      exit 1
    end
  end

  desc "Initialize backup system (creates first backup and sets up tracking)"
  task init_backup: :environment do
    puts "Initializing backup system..."
    
    # Create initial backup
    result = BackupService.backup
    
    if result[:success]
      puts "✓ Backup system initialized successfully!"
      puts "Auto-backup will now run with smart timing logic."
    else
      puts "✗ Backup system initialization failed: #{result[:error]}"
      exit 1
    end
  end

  desc "List available backups"
  task list_backups: :environment do
    backup_dir = BackupService.backup_dir
    if Dir.exist?(backup_dir)
      backups = Dir.glob("#{backup_dir}/*.sql").sort_by { |f| File.mtime(f) }.reverse
      if backups.empty?
        puts "No backups found in #{backup_dir}"
      else
        puts "Available backups:"
        backups.each do |backup|
          size = File.size(backup)
          mtime = File.mtime(backup)
          puts "  #{File.basename(backup)} (#{size} bytes, #{mtime})"
        end
      end
    else
      puts "Backup directory #{backup_dir} does not exist"
    end
  end

  desc "Clean old backups (keep last 5)"
  task clean_backups: :environment do
    backup_dir = BackupService.backup_dir
    if Dir.exist?(backup_dir)
      backups = Dir.glob("#{backup_dir}/*.sql").sort_by { |f| File.mtime(f) }
      keep_count = BackupService.keep_backup_count
      if backups.length > keep_count
        to_delete = backups[0...-keep_count]
        puts "Deleting #{to_delete.length} old backups..."
        to_delete.each do |backup|
          File.delete(backup)
          puts "  Deleted: #{File.basename(backup)}"
        end
      else
        puts "No old backups to clean (keeping #{backups.length} backups)"
      end
    else
      puts "Backup directory #{backup_dir} does not exist"
    end
  end

  desc "Check PostgreSQL setup and versions"
  task check_pg_setup: :environment do
    puts "=== PostgreSQL Setup Check ==="
    
    # Use BackupService to check compatibility
    compatibility = BackupService.version_compatibility_check
    
    if compatibility[:pg_dump_available]
      puts "✓ pg_dump found: #{compatibility[:pg_dump_version]}"
    else
      puts "✗ pg_dump not found or not in PATH"
      puts "  Please install PostgreSQL client tools"
      exit 1
    end
    
    if compatibility[:server_version]
      puts "✓ PostgreSQL server version: #{compatibility[:server_version]}"
    else
      puts "✗ Could not determine PostgreSQL server version"
      exit 1
    end
    
    if compatibility[:compatible]
      puts "✓ Version compatibility: OK"
    else
      puts "⚠️  Version compatibility: WARNING"
      puts "   pg_dump version may not be compatible with server version"
    end
    
    # Check database connection
    begin
      db_config = Rails.application.config.database_configuration[Rails.env]
      puts "✓ Database config found for #{Rails.env} environment"
      puts "  Database: #{db_config['database']}"
      puts "  Username: #{db_config['username']}"
      puts "  Host: #{db_config['host'] || 'localhost'}"
      
      # Test connection
      ActiveRecord::Base.connection.execute("SELECT version()")
      puts "✓ Database connection successful"
      
    rescue => e
      puts "✗ Database connection failed: #{e.message}"
      exit 1
    end
    
    puts "\n=== Backup Configuration ==="
    puts "Config file: #{BackupService::CONFIG_FILE}"
    puts "Backup directory: #{BackupService.backup_dir}"
    puts "Database name: #{BackupService.db_name}"
    puts "Backup method: #{BackupService.backup_method}"
    puts "Minimum interval: #{BackupService.min_backup_interval / 1.hour} hours"
    puts "Force interval: #{BackupService.force_backup_interval / 1.hour} hours"
    puts "Emergency interval: #{BackupService.emergency_backup_interval / 1.day} days"
    puts "Keep backup count: #{BackupService.keep_backup_count}"
    puts "Batch size: #{BackupService.batch_size}"
  end

  # ============================================================================
  # Rails-based backup tasks (completely separate from pg_dump tasks)
  # ============================================================================
  
  desc "Rails backup the database (ActiveRecord-based, no pg_dump required)"
  task rails_backup: :environment do
    result = BackupService.rails_backup
    
    if result[:success]
      puts "✓ Rails backup completed successfully: #{result[:file]} (#{result[:size]} bytes)"
    else
      puts "✗ Rails backup failed: #{result[:error]}"
      exit 1
    end
  end

  desc "Rails auto backup with smart timing logic (ActiveRecord-based)"
  task rails_auto_backup: :environment do
    result = BackupService.rails_auto_backup
    
    if result[:success]
      puts "✓ Rails backup created: #{result[:reason]}"
    elsif result[:skipped]
      puts "⏭ Rails backup skipped: #{result[:reason]}"
    else
      puts "✗ Rails backup failed: #{result[:error]}"
      exit 1
    end
  end

  desc "Initialize Rails backup system (creates first Rails backup)"
  task rails_init_backup: :environment do
    puts "Initializing Rails backup system..."
    
    result = BackupService.rails_backup
    
    if result[:success]
      puts "✓ Rails backup system initialized successfully!"
      puts "Rails auto-backup will now run with smart timing logic."
    else
      puts "✗ Rails backup system initialization failed: #{result[:error]}"
      exit 1
    end
  end

  desc "List available Rails backups"
  task rails_list_backups: :environment do
    backup_service = BackupService.new
    backups = backup_service.rails_list_backups
    
    if backups.empty?
      puts "No Rails backups found in #{BackupService.backup_dir}"
    else
      puts "Available Rails backups:"
      backups.each do |backup|
        puts "  #{backup[:filename]} (#{backup[:size]} bytes, #{backup[:created_at]})"
      end
    end
  end

  desc "Clean old Rails backups (keep last 5)"
  task rails_clean_backups: :environment do
    backup_service = BackupService.new
    backup_service.rails_cleanup_old_backups
    puts "Rails backup cleanup completed"
  end

  desc "Check Rails backup system status"
  task rails_check_status: :environment do
    backup_service = BackupService.new
    
    puts "=== Rails Backup System Status ==="
    puts "Last Rails backup: #{backup_service.rails_last_backup_time&.strftime('%Y-%m-%d %H:%M:%S') || 'Never'}"
    puts "Time since last: #{backup_service.rails_time_since_last_backup / 1.hour} hours"
    puts "Should backup: #{backup_service.rails_should_backup?}"
    puts "Available backups: #{backup_service.rails_list_backups.count}"
    
    if backup_service.rails_should_backup?
      puts "Status: NEEDS_BACKUP"
    else
      puts "Status: UP_TO_DATE"
    end
  end

  # ============================================================================
  # Both backup methods (pg_dump + Rails)
  # ============================================================================

  desc "Both backup methods (pg_dump + Rails) - immediate execution"
  task both_backup: :environment do
    result = BackupService.both_backup
    
    puts "=== Both Backup Methods Results ==="
    
    if result[:pg_dump]
      pg_result = result[:pg_dump]
      if pg_result[:success]
        puts "✓ pg_dump: #{pg_result[:file]}"
      else
        puts "✗ pg_dump: #{pg_result[:error]}"
      end
    end
    
    if result[:rails]
      rails_result = result[:rails]
      if rails_result[:success]
        puts "✓ Rails: #{rails_result[:file]} (#{rails_result[:size]} bytes)"
      else
        puts "✗ Rails: #{rails_result[:error]}"
      end
    end
    
    # Determine overall success
    pg_success = result[:pg_dump]&.dig(:success) || false
    rails_success = result[:rails]&.dig(:success) || false
    
    if pg_success && rails_success
      puts "\n✓ Both backup methods completed successfully!"
    elsif pg_success || rails_success
      successful_method = pg_success ? 'pg_dump' : 'rails'
      puts "\n⚠️  Only #{successful_method} backup completed successfully"
    else
      puts "\n✗ Both backup methods failed"
      exit 1
    end
  end

  desc "Both backup methods (pg_dump + Rails) with smart timing logic"
  task both_auto_backup: :environment do
    result = BackupService.both_auto_backup
    
    if result[:success]
      puts "✓ Both backups created: #{result[:reason]}"
      
      # Show detailed results if available
      if result[:results]
        puts "\nDetailed results:"
        if result[:results][:pg_dump]
          pg_result = result[:results][:pg_dump]
          if pg_result[:success]
            puts "  ✓ pg_dump: #{pg_result[:file]}"
          else
            puts "  ✗ pg_dump: #{pg_result[:error]}"
          end
        end
        
        if result[:results][:rails]
          rails_result = result[:results][:rails]
          if rails_result[:success]
            puts "  ✓ Rails: #{rails_result[:file]} (#{rails_result[:size]} bytes)"
          else
            puts "  ✗ Rails: #{rails_result[:error]}"
          end
        end
      end
    elsif result[:skipped]
      puts "⏭ Both backups skipped: #{result[:reason]}"
    else
      puts "✗ Both backups failed: #{result[:error]}"
      exit 1
    end
  end

  desc "Generate or show backup configuration"
  task config: :environment do
    config_file = BackupService::CONFIG_FILE
    
    if File.exist?(config_file)
      puts "=== Current Backup Configuration ==="
      puts "Config file: #{config_file}"
      puts ""
      puts File.read(config_file)
      puts ""
      puts "To modify the configuration, edit: #{config_file}"
    else
      puts "=== Generating Default Backup Configuration ==="
      BackupService.generate_default_config
      puts "Default configuration generated at: #{config_file}"
      puts "Please review and modify the configuration as needed."
    end
  end

  desc "Show backup configuration help"
  task config_help: :environment do
    puts "=== Backup Configuration Help ==="
    puts ""
    puts "Configuration file: #{BackupService::CONFIG_FILE}"
    puts ""
    puts "Available settings:"
    puts "  backup_dir: Directory to store backup files (can be external path)"
    puts "  db_name: Database name to backup"
    puts "  min_backup_interval_hours: Minimum time between backups (default: 6)"
    puts "  force_backup_interval_hours: Force backup after this time (default: 24)"
    puts "  emergency_backup_interval_days: Emergency backup after this time (default: 7)"
    puts "  keep_backup_count: Number of backups to keep (default: 5)"
    puts "  batch_size: Number of rows to process in batches (default: 1000)"
    puts ""
    puts "Example external backup directory:"
    puts "  backup_dir: '/mnt/external_drive/backups'  # Linux/Mac"
    puts "  backup_dir: 'D:\\Backups\\Database'        # Windows"
    puts ""
    puts "Commands:"
    puts "  rake db:config          # Show current configuration"
    puts "  rake db:config_help     # Show this help"
    puts "  rake db:rails_init_backup  # Initialize Rails backup system"
  end
end 