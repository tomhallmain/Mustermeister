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
    backup_dir = "db_backups"
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
    backup_dir = "db_backups"
    if Dir.exist?(backup_dir)
      backups = Dir.glob("#{backup_dir}/*.sql").sort_by { |f| File.mtime(f) }
      if backups.length > 5
        to_delete = backups[0...-5]
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
    
    # Check if pg_dump is available
    if Gem.win_platform?
      pg_dump_version = `pg_dump --version 2>&1`
    else
      pg_dump_version = `pg_dump --version 2>&1`
    end
    
    if $?.success?
      puts "✓ pg_dump found: #{pg_dump_version.strip}"
    else
      puts "✗ pg_dump not found or not in PATH"
      puts "  Please install PostgreSQL client tools"
      exit 1
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
      
      # Get server version
      server_version = ActiveRecord::Base.connection.execute("SHOW server_version").first['server_version']
      puts "✓ PostgreSQL server version: #{server_version}"
      
    rescue => e
      puts "✗ Database connection failed: #{e.message}"
      exit 1
    end
    
    puts "\n=== Backup Configuration ==="
    backup_service = BackupService.new
    puts "Backup directory: #{BackupService::BACKUP_DIR}"
    puts "Database name: #{BackupService::DB_NAME}"
    puts "Minimum interval: #{BackupService::MIN_BACKUP_INTERVAL / 1.hour} hours"
    puts "Force interval: #{BackupService::FORCE_BACKUP_INTERVAL / 1.hour} hours"
    puts "Emergency interval: #{BackupService::EMERGENCY_BACKUP_INTERVAL / 1.day} days"
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
      puts "No Rails backups found in #{BackupService::BACKUP_DIR}"
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
end 