module PostgresConnectionChecker
    def self.check!
        require 'pg'
        require 'erb'
    
        # Load database configuration
        database_yml = Rails.root.join('config/database.yml')
        yaml_content = ERB.new(File.read(database_yml)).result
        db_config = YAML.safe_load(yaml_content, aliases: true)[Rails.env]

        unless verify_database_connection(db_config, false)
            start_postgres_service(db_config)
        end
    rescue => e
        abort "Critical error during PostgreSQL check: #{e.message}"
    end


    private
    def self.start_postgres_service(db_config)
        puts "Attempting to start PostgreSQL service..."
        # If user specified a service name in environment variable, use that
        service_name = ENV['POSTGRES_SERVICE']
        if RbConfig::CONFIG['host_os'] =~ /mswin|mingw|cygwin/
            start_postgres_service_windows(db_config, service_name)
        elsif RbConfig::CONFIG['host_os'] =~ /linux/
            start_postgres_service_linux(db_config, service_name)
        elsif RbConfig::CONFIG['host_os'] =~ /darwin/
            start_postgres_service_macos(db_config, service_name)
        else
            puts "This PostgreSQL service start task is currently only supported on Windows, Linux, and macOS"
            exit 1
        end
    end


    private
    def self.verify_database_connection(db_config, do_retry = false)
        # Extract connection parameters
        host     = db_config['host'] || 'localhost'
        port     = db_config['port'] || 5432
        database = db_config['database']
        username = db_config['username']
        password = db_config['password']

        max_attempts = 10
        attempt = 0
        delay = 1 # seconds
  
        loop do
            begin
                conn = PG.connect(host: host, port: port, dbname: database, user: username, password: password)
                conn.close
                puts "Successfully connected to PostgreSQL"
                return true
            rescue PG::ConnectionBad => e
                unless do_retry
                    puts "PostgreSQL connection failed: #{e.message}."
                    return false
                end
                attempt += 1
                if attempt >= max_attempts
                    puts "Failed to connect to PostgreSQL after #{max_attempts} attempts"
                    return false
                end
                puts "Waiting for PostgreSQL to be ready (attempt #{attempt}/#{max_attempts})..."
                sleep delay
            end
        end
    end


    private
    def self.parse_service_names(postgres_services, use_x64 = false)
        puts "Found PostgreSQL services: #{postgres_services.join(', ')}"
        # Find service closest to version 17, or highest version
        if use_x64
            service_name = postgres_services.min_by do |service|
                version = service.match(/x64-(\d+)/)&.captures&.first&.to_i
                if version.nil?
                    # For non-x64 services, try to find the highest version number
                    version = service.match(/\d+/)&.to_s&.to_i
                    # If no version found, put it at the end of the list
                    version.nil? ? 9999 : version * -1
                else
                    # For x64 services, find closest to version 17
                    (version - 17).abs
                end
            end
        else
            # Find latest version (assumes naming convention with versions)
            service_name = postgres_services.min_by do |service|
                version = service.match(/\d+/)&.to_s&.to_i
                version.nil? ? 9999 : (version - 17).abs
            end
        end
        puts "Selected service: #{service_name}"
        return service_name
    end


    private
    def self.is_admin_windows?
        begin
            require 'win32/security'
            Win32::Security::SID::Administrators.included_in?(Win32::Security::SID::CurrentUser)
        rescue LoadError
            # If win32-security gem is not available, try a simpler check
            system('net session >nul 2>&1')
        end
    end


    private
    def self.start_postgres_service_windows(db_config, service_name = nil)
        puts "Detected Windows system"

        begin
            unless service_name
                # Get list of all services
                services_output = `sc query type= service state= all`

                # Find all PostgreSQL services
                postgres_services = services_output.scan(/SERVICE_NAME\s*:\s*(postgresql.*)/)
                    .flatten
                    .select { |name| name.downcase.include?('postgresql') }
                
                if postgres_services.empty?
                    puts "No PostgreSQL services found. Please ensure PostgreSQL is installed."
                    exit 1
                end

                service_name = parse_service_names(postgres_services)
            end

            unless is_admin_windows?
                puts "Error: Administrative privileges are required to start PostgreSQL service."
                puts "Please run 'rails server' as administrator or start the PostgreSQL service manually."
                puts "To start the PostgreSQL service in an elevated command prompt, run the following command:"
                puts "      net start #{service_name}"
                exit 1
            end

            puts "Starting PostgreSQL service: #{service_name}"
            system("net start #{service_name}")
            sleep 2 # Allow time for service startup
            puts "PostgreSQL service started successfully"
            
            # Verify the database is actually ready to accept connections
            unless verify_database_connection(db_config, true)
                puts "Failed to verify database connection. Please check your PostgreSQL installation."
                exit 1
            end
        rescue => e
            puts "Failed to start PostgreSQL service #{service_name}: #{e.message}"
            exit 1
        end
    end

    private
    def self.start_postgres_service_linux(db_config, service_name = nil)
        puts "Detected Linux system"

        begin
            unless service_name
                # Find installed PostgreSQL services
                services = `systemctl list-unit-files --type=service | grep -E 'postgresql.*service'`
                            .lines
                            .map { |line| line.split.first }
                            .select { |name| name.include?('postgresql') }

                if services.empty?
                    puts "No PostgreSQL services found via systemctl. Checking init.d..."
                    services = Dir.glob('/etc/init.d/postgresql*')
                                .map { |path| File.basename(path) }
                end

                if services.empty?
                    puts "Error: No PostgreSQL services found".red
                    exit 1
                end

                service_name = parse_service_names(services)
            end

            # Check for sudo privileges
            unless system('sudo -v >/dev/null 2>&1')
                puts <<~ERROR.red
                Error: sudo privileges required to start PostgreSQL.
                Please run one of these commands:
                - sudo systemctl start #{service_name}
                - sudo rails server
                ERROR
                exit 1
            end

            # Attempt to start service
            if system("sudo systemctl start #{service_name}")
                puts "Successfully started #{service_name}".green
                sleep 2 # Allow time for service startup
                return if verify_database_connection(db_config, true)
            end

            puts "Failed to start PostgreSQL service #{service_name}".red
            exit 1
        rescue => e
            puts "Failed to start PostgreSQL service #{service_name}: #{e.message}"
            exit 1
        end
    end

    private
    def self.start_postgres_service_macos(db_config, service_name = nil)
        puts "Detected macOS system"

        begin
            unless service_name
                # Get list of available PostgreSQL services via Homebrew
                services = `brew services list | grep postgresql`.lines.map do |line|
                    line.split.first.gsub(/@.*/, '') # Handle versioned services like postgresql@14
                end.uniq
            
                if services.empty?
                    puts "Error: No PostgreSQL services found via Homebrew".red
                    exit 1
                end
            
                service_name = parse_service_names(services)
            end

            # Start service
            if system("brew services start #{best_service}")
                puts "Successfully started #{best_service}".green
                sleep 2 # Allow time for service startup
                return if verify_database_connection(db_config, true)
            end
        
            puts <<~ERROR.red
                Failed to start PostgreSQL service. You might need to run:
                brew services start #{best_service}
            ERROR
            exit 1
        rescue => e
            puts "Failed to start PostgreSQL service #{service_name}: #{e.message}"
            exit 1
        end
    end
end
