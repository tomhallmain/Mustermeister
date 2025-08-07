namespace :i18n do
  desc "Run i18n-tasks commands without spam"
  task :tasks, :command_args do |_, args|
    command = args[:command_args] || ''
    parts = command.split(',')
    base_command = parts.shift
    
    unless valid_commands.include?(base_command)
      puts "Invalid command: #{base_command}"
      exit(1)
    end
    
    run_i18n_clean(base_command)
  end

  desc "Check for missing translations"
  task missing: :environment do
    puts "Checking for missing translations..."
    
    # Find all translation keys used in the application
    used_keys = []
    
    # Scan ERB files for translation calls
    Dir.glob(Rails.root.join('app/views/**/*.erb')).each do |file|
      content = File.read(file)
      content.scan(/t\(['"`]([^'"`]+)['"`]/).each do |match|
        used_keys << match[0]
      end
      content.scan(/I18n\.t\(['"`]([^'"`]+)['"`]/).each do |match|
        used_keys << match[0]
      end
    end
    
    # Scan Ruby files for translation calls
    Dir.glob(Rails.root.join('app/**/*.rb')).each do |file|
      content = File.read(file)
      content.scan(/t\(['"`]([^'"`]+)['"`]/).each do |match|
        used_keys << match[0]
      end
      content.scan(/I18n\.t\(['"`]([^'"`]+)['"`]/).each do |match|
        used_keys << match[0]
      end
    end
    
    used_keys.uniq!
    
    # Check which keys are missing
    missing_keys = []
    used_keys.each do |key|
      begin
        I18n.t(key)
      rescue I18n::MissingTranslationData
        missing_keys << key
      end
    end
    
    if missing_keys.empty?
      puts "✓ No missing translations found!"
    else
      puts "Missing translations:"
      missing_keys.each { |key| puts "  - #{key}" }
    end
  end

  desc "Find unused translation keys"
  task unused: :environment do
    puts "Checking for unused translation keys..."
    
    # Get all defined translation keys
    defined_keys = []
    I18n.backend.send(:init_translations)
    collect_keys(I18n.backend.send(:translations), defined_keys)
    
    # Find all translation keys used in the application
    used_keys = []
    
    # Scan ERB files for translation calls
    Dir.glob(Rails.root.join('app/views/**/*.erb')).each do |file|
      content = File.read(file)
      content.scan(/t\(['"`]([^'"`]+)['"`]/).each do |match|
        used_keys << match[0]
      end
      content.scan(/I18n\.t\(['"`]([^'"`]+)['"`]/).each do |match|
        used_keys << match[0]
      end
    end
    
    # Scan Ruby files for translation calls
    Dir.glob(Rails.root.join('app/**/*.rb')).each do |file|
      content = File.read(file)
      content.scan(/t\(['"`]([^'"`]+)['"`]/).each do |match|
        used_keys << match[0]
      end
      content.scan(/I18n\.t\(['"`]([^'"`]+)['"`]/).each do |match|
        used_keys << match[0]
      end
    end
    
    used_keys.uniq!
    
    # Find unused keys
    unused_keys = defined_keys - used_keys
    
    if unused_keys.empty?
      puts "✓ No unused translation keys found!"
    else
      puts "Unused translation keys:"
      unused_keys.each { |key| puts "  - #{key}" }
    end
  end

  desc "Normalize locale files (sort keys alphabetically)"
  task normalize: :environment do
    puts "Normalizing locale files..."
    
    Dir.glob(Rails.root.join('config/locales/**/*.yml')).each do |file|
      puts "Processing #{file}..."
      normalize_yaml_file(file)
    end
    
    puts "✓ Locale files normalized!"
  end

  desc "Show translation statistics (use [true] to consider fallbacks)"
  task :stats, [:consider_fallbacks] => :environment do |t, args|
    consider_fallbacks = args[:consider_fallbacks] == 'true'
    
    puts "Translation Statistics:"
    puts "======================"
    puts "Fallback consideration: #{consider_fallbacks ? 'enabled' : 'disabled'}"
    puts ""
    
    I18n.available_locales.each do |locale|
      if consider_fallbacks
        # Count actual keys in this locale (not fallbacks)
        actual_keys = count_actual_keys(locale)
        fallback_keys = count_fallback_keys(locale)
        total_keys = actual_keys + fallback_keys
        
        puts "#{locale}: #{actual_keys} actual keys, #{fallback_keys} fallback keys (#{total_keys} total)"
      else
        # Count only actual keys in this locale
        actual_keys = count_actual_keys(locale)
        puts "#{locale}: #{actual_keys} actual keys"
      end
    end
    
    puts "\nDetailed Breakdown:"
    puts "=================="
    I18n.available_locales.each do |locale|
      next if locale == I18n.default_locale
      
      missing_keys = find_missing_keys(locale, consider_fallbacks, 15)
      if missing_keys.any?
        puts "\n#{locale.upcase} - Missing translations:"
        missing_keys.first(10).each { |key| puts "  #{key}" }
        puts "  ... and (at least) #{missing_keys.count - 10} more" if missing_keys.count > 10
      else
        puts "\n#{locale.upcase} - All translations present"
      end
    end
  end

  desc "Check for missing translations across all locales (use [true] to consider fallbacks)"
  task :missing_locales, [:consider_fallbacks] => :environment do |t, args|
    consider_fallbacks = args[:consider_fallbacks] == 'true'
    
    puts "Checking for missing translations across locales..."
    puts "=================================================="
    puts "Fallback consideration: #{consider_fallbacks ? 'enabled' : 'disabled'}"
    puts ""
    
    # Get all English keys as the baseline
    english_keys = get_all_keys(:en)
    puts "English baseline: #{english_keys.count} keys"
    
    I18n.available_locales.each do |locale|
      next if locale == :en
      
      puts "\n#{locale.upcase}:"
      if consider_fallbacks
        # Consider fallbacks - only show keys that are truly missing
        # Use limit of 10 since we only show 5 in output anyway
        missing_keys = find_missing_keys(locale, true, 10)
      else
        # Don't consider fallbacks - show all keys not explicitly defined
        locale_keys = get_all_keys(locale)
        missing_keys = english_keys - locale_keys
      end
      
      if missing_keys.empty?
        puts "  ✓ All translations present"
      else
        puts "  ✗ Missing #{missing_keys.count} translations:"
        missing_keys.first(5).each { |key| puts "    - #{key}" }
        puts "    ... and (at least) #{missing_keys.count - 5} more" if missing_keys.count > 5
      end
    end
  end

  private

  def count_actual_keys(locale)
    # Count keys that actually exist in this locale (not fallbacks)
    I18n.backend.send(:init_translations)
    translations = I18n.backend.send(:translations)[locale] || {}
    keys = []
    collect_keys(translations, keys)
    keys.count
  end

  def count_fallback_keys(locale)
    # Count keys that are available through fallbacks
    return 0 if locale == I18n.default_locale
    
    english_keys = get_all_keys(:en)
    locale_keys = get_all_keys(locale)
    (english_keys - locale_keys).count
  end

  def find_missing_keys(locale, consider_fallbacks = false, limit = -1)
    # Find keys that are missing in this locale
    return [] if locale == I18n.default_locale
    
    english_keys = get_all_keys(:en)
    locale_keys = get_all_keys(locale)
    
    if consider_fallbacks
      # Consider fallbacks - only show keys that are truly missing
      # This means keys that would cause I18n::MissingTranslationData when accessed
      missing_keys = []
      english_keys.each do |key|
        # Check if the translation exists in this locale without fallbacks
        begin
          # Use a different approach: check if the key exists in the backend directly
          backend = I18n.backend
          backend.send(:init_translations)
          translations = backend.send(:translations)[locale] || {}
           
          # Navigate to the key in the translations hash
          key_parts = key.split('.')
          current = translations
          key_exists = true
           
          key_parts.each do |part|
            if current.is_a?(Hash) && current.key?(part.to_sym)
              current = current[part.to_sym]
            else
              key_exists = false
              break
            end
          end
           
          missing_keys << key unless key_exists
          
          # Early exit if we've reached the limit
          break if limit > 0 && missing_keys.count >= limit
        rescue => e
          # If there's any error checking the key, consider it missing
          missing_keys << key
          
          # Early exit if we've reached the limit
          break if limit > 0 && missing_keys.count >= limit
        end
      end
      missing_keys
    else
      # Don't consider fallbacks - show all keys not explicitly defined
      english_keys - locale_keys
    end
  end

  def get_all_keys(locale)
    I18n.backend.send(:init_translations)
    translations = I18n.backend.send(:translations)[locale] || {}
    keys = []
    collect_keys(translations, keys)
    keys
  end

  def collect_keys(hash, keys, prefix = '')
    hash.each do |key, value|
      current_key = prefix.empty? ? key.to_s : "#{prefix}.#{key}"
      if value.is_a?(Hash)
        collect_keys(value, keys, current_key)
      else
        keys << current_key
      end
    end
  end

  def normalize_yaml_file(file_path)
    require 'yaml'
    
    content = File.read(file_path)
    yaml = YAML.load(content)
    
    # Sort keys recursively
    sorted_yaml = sort_hash(yaml)
    
    # Write back to file with proper formatting
    File.write(file_path, sorted_yaml.to_yaml)
  end

  def sort_hash(hash)
    hash.keys.sort.each_with_object({}) do |key, sorted_hash|
      value = hash[key]
      sorted_hash[key] = value.is_a?(Hash) ? sort_hash(value) : value
    end
  end

  def valid_commands
    @valid_commands ||= %w[
      unused missing translate normalize
      add-missing health config find
    ]
  end

  def run_i18n_clean(command)
    require 'open3'
    Open3.popen2e("bundle exec i18n-tasks #{command}") do |_, output, wait_thr|
      output.each do |line|
        # Remove spam messages
        puts line unless line.include?("Ukraine")
      end
      exit wait_thr.value.exitstatus
    end
  end
end
