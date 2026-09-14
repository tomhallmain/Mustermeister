require 'zip'
require 'openssl'
require 'csv'

class UserDataService
  SUPPORTED_FORMATS = %w[json encrypted_zip].freeze

  # Accepted TSV header names - matched by name (CSV `headers: true`), not
  # position, so this is not a required column order. Listed here once as
  # the single source of truth so the profile view's help text doesn't have
  # to duplicate a literal, language-independent list in every locale.
  TSV_IMPORT_COLUMNS = %w[Project Title Description Priority Status].freeze

  class << self
    def export_data(user, format: 'json', password: nil)
      new(user).export_data(format, password)
    end
    
    def import_data(user, file, password: nil, require_existing_projects: false)
      new(user).import_data(file, password, require_existing_projects: require_existing_projects)
    end
    
    def validate_import_file(file)
      new(nil).validate_import_file(file)
    end
  end
  
  def initialize(user)
    @user = user
  end
  
  def export_data(format, password = nil)
    case format.to_s.downcase
    when 'json'
      export_json
    when 'encrypted_zip'
      export_encrypted_zip(password)
    else
      { success: false, error: "Unsupported format: #{format}" }
    end
  rescue => e
    { success: false, error: "Export failed: #{e.message}" }
  end
  
  def import_data(file, password = nil, require_existing_projects: false)
    begin
      file_extension = File.extname(file.original_filename).downcase

      case file_extension
      when '.json'
        import_json(file, require_existing_projects: require_existing_projects)
      when '.zip'
        import_encrypted_zip(file, password, require_existing_projects: require_existing_projects)
      when '.tsv'
        import_tsv(file, require_existing_projects: require_existing_projects)
      else
        { success: false, error: "Unsupported file format. Please use .json, .tsv, or .zip files." }
      end
    rescue => e
      { success: false, error: "Import failed: #{e.message}" }
    end
  end
  
  def validate_import_file(file)
    return { valid: false, error: "No file provided" } unless file
    return { valid: false, error: "No file provided" } unless file.respond_to?(:original_filename) && file.respond_to?(:size)

    file_extension = File.extname(file.original_filename).downcase
    max_size = 50.megabytes # 50MB limit
    
    if file.size > max_size
      return { valid: false, error: "File too large. Maximum size is #{max_size / 1.megabyte}MB" }
    end
    
    unless ['.json', '.zip', '.tsv'].include?(file_extension)
      return { valid: false, error: "Unsupported file format. Please use .json, .tsv, or .zip files." }
    end
    
    { valid: true, format: file_extension }
  end
  
  private
  
  def export_json
    data = collect_user_data
    filename = generate_filename('json')
    
    { 
      success: true, 
      data: data.to_json, 
      filename: filename,
      format: 'json',
      size: data.to_json.bytesize
    }
  end
  
  def export_encrypted_zip(password)
    data = collect_user_data
    json_data = data.to_json
    
    # Compress the data
    compressed_data = Zlib::Deflate.deflate(json_data)
    
    # Encrypt the compressed data
    encrypted_data = encrypt_data(compressed_data, password)
    
    # Create ZIP file with encrypted data
    zip_data = create_zip_file(encrypted_data)
    
    filename = generate_filename('zip')
    
    { 
      success: true, 
      data: zip_data, 
      filename: filename,
      format: 'encrypted_zip',
      size: zip_data.bytesize,
      original_size: json_data.bytesize,
      compression_ratio: (json_data.bytesize.to_f / zip_data.bytesize).round(2)
    }
  end
  
  def import_json(file, require_existing_projects: false)
    json_content = file.read
    data = JSON.parse(json_content)

    import_user_data(data, require_existing_projects: require_existing_projects)
  end

  def import_encrypted_zip(file, password, require_existing_projects: false)
    # Extract ZIP file
    zip_content = file.read
    encrypted_data = extract_from_zip(zip_content)

    # Decrypt the data
    compressed_data = decrypt_data(encrypted_data, password)

    # Decompress the data
    json_data = Zlib::Inflate.inflate(compressed_data)

    # Parse JSON
    data = JSON.parse(json_data)

    import_user_data(data, require_existing_projects: require_existing_projects)
  end

  # A lightweight companion to the JSON/ZIP account backup above: a flat,
  # tab-separated task list (see TSV_IMPORT_COLUMNS for the accepted header
  # names) rather than a full account export. Columns are matched by header
  # name, not position, so the header row's column order is not fixed.
  # No comments/tags/timestamps - just enough to bulk-create or update tasks,
  # grouped into projects by the Project column. skip_blanks guards against a
  # trailing blank line, which would otherwise surface as a spurious "Title
  # can't be blank" error.
  def import_tsv(file, require_existing_projects: false)
    ActiveRecord::Base.transaction do
      # liberal_parsing: real-world TSV (hand-authored, pasted from a note-
      # taking app, etc.) commonly has a stray, unescaped `"` inside an
      # otherwise-unquoted field (e.g. a description quoting an error
      # message) - strict RFC 4180 parsing rejects that outright as
      # "Illegal quoting", so treat quotes leniently instead of failing the
      # whole import over an incidental character.
      rows = CSV.parse(file.read, col_sep: "\t", headers: true, skip_blanks: true, liberal_parsing: true)

      if require_existing_projects
        ensure_projects_exist!(rows.map { |row| row['Project'].to_s.strip })
      end

      imported_tasks = rows.map { |row| import_tsv_task_row(row) }

      {
        success: true,
        imported: {
          projects: imported_tasks.map(&:project_id).uniq.count,
          tasks: imported_tasks.count,
          tags: 0,
          comments: 0
        }
      }
    end
  rescue => e
    { success: false, error: "Import failed: #{e.message}" }
  end

  def import_tsv_task_row(row)
    project = @user.projects.find_or_initialize_by(title: row['Project'].to_s.strip)
    # See import_projects - restoring the user's own data, not a fresh
    # submission, so the similar-title warning doesn't apply here.
    project.confirm_duplicate = true
    project.save!
    project.create_default_statuses! if project.statuses.empty?

    status_name = row['Status'].to_s.strip
    status = status_name.present? ? project.statuses.find_by(name: status_name) : nil
    status ||= project.status_by_key(:not_started)

    task = project.tasks.find_or_initialize_by(title: row['Title'].to_s.strip)
    task.assign_attributes(
      user: @user,
      priority: row['Priority'].to_s.strip.downcase.presence,
      description: row['Description'],
      status: status,
      # See import_project_tasks - same reasoning, same bypass.
      skip_duplicate_check: true
    )
    task.save!
    task
  end

  # Shared by the TSV and JSON/ZIP import paths: when require_existing_projects
  # is set, a project name that doesn't already exist for this user must
  # abort the whole import (nothing created or updated) rather than silently
  # creating a new project - the usual failure mode being a typo'd project
  # name in a hand-authored TSV file.
  def ensure_projects_exist!(project_names)
    missing = project_names.uniq - @user.projects.pluck(:title)
    return if missing.empty?

    raise I18n.t('views.users.profile.unknown_projects_error', projects: missing.join(', '))
  end

  def collect_user_data
    {
      export_info: {
        exported_at: Time.current.iso8601,
        user_id: @user.id,
        user_email: @user.email,
        version: '1.0',
        format: 'mustermeister_user_data'
      },
      user: {
        id: @user.id,
        email: @user.email,
        name: @user.name,
        created_at: @user.created_at,
        updated_at: @user.updated_at
      },
      # No separate "standalone tasks" bucket - Task#project_id is a required
      # column and tasks are only ever created nested under a project, so
      # every task is reachable via its project below.
      projects: @user.projects.map do |project|
        {
          id: project.id,
          name: project.title,
          description: project.description,
          priority: project.default_priority,
          created_at: project.created_at,
          updated_at: project.updated_at,
          last_activity_at: project.last_activity_at,
          statuses: project.statuses.map do |status|
            {
              id: status.id,
              name: status.name,
              created_at: status.created_at,
              updated_at: status.updated_at
            }
          end,
          tasks: project.tasks.map do |task|
            {
              id: task.id,
              title: task.title,
              description: task.description,
              priority: task.priority,
              due_date: task.due_date,
              estimated_minutes: task.estimated_minutes,
              scheduled_at: task.scheduled_at,
              completed: task.completed,
              completed_at: task.completed_at,
              completed_by: task.completed_by,
              archived: task.archived,
              archived_at: task.archived_at,
              created_at: task.created_at,
              updated_at: task.updated_at,
              status_name: task.status&.name, # Export status name instead of ID
              comments: task.comments.map do |comment|
                {
                  id: comment.id,
                  content: comment.content,
                  status: comment.status,
                  created_at: comment.created_at,
                  updated_at: comment.updated_at
                }
              end,
              tags: task.tags.map do |tag|
                {
                  id: tag.id,
                  name: tag.name
                }
              end
            }
          end,
          comments: project.comments.map do |comment|
            {
              id: comment.id,
              content: comment.content,
              status: comment.status,
              created_at: comment.created_at,
              updated_at: comment.updated_at
            }
          end
        }
      end,
      tags: @user.tasks.joins(:tags).distinct.pluck('tags.id', 'tags.name', 'tags.created_at', 'tags.updated_at').map do |tag_data|
        {
          id: tag_data[0],
          name: tag_data[1],
          created_at: tag_data[2],
          updated_at: tag_data[3]
        }
      end
    }
  end
  
  def import_user_data(data, require_existing_projects: false)
    ActiveRecord::Base.transaction do
      # Validate data structure
      unless data['export_info'] && data['user']
        raise "Invalid data format. Missing required export information."
      end

      if require_existing_projects
        ensure_projects_exist!((data['projects'] || []).map { |p| p['name'].to_s.strip })
      end

      # Import tags first (they might be referenced by tasks)
      imported_tags = import_tags(data['tags'] || [])

      # Import projects and their tasks
      imported_projects = import_projects(data['projects'] || [], imported_tags)

      {
        success: true,
        imported: {
          projects: imported_projects.count,
          tasks: imported_projects.sum { |p| p.tasks.count },
          tags: imported_tags.count,
          comments: imported_projects.sum { |p| p.comments.count } +
                   imported_projects.sum { |p| p.tasks.sum { |t| t.comments.count } }
        }
      }
    end
  rescue => e
    { success: false, error: "Import failed: #{e.message}" }
  end
  
  def import_tags(tags_data)
    tags_data.map do |tag_data|
      tag = Tag.find_or_initialize_by(name: tag_data['name'])
      tag.assign_attributes(
        created_at: tag_data['created_at'],
        updated_at: tag_data['updated_at']
      )
      tag.save!
      tag
    end
  end
  
  def import_projects(projects_data, imported_tags)
    projects_data.map do |project_data|
      project = @user.projects.find_or_initialize_by(title: project_data['name'])
      project.assign_attributes(
        description: project_data['description'],
        default_priority: project_data['priority'],
        created_at: project_data['created_at'],
        updated_at: project_data['updated_at'],
        last_activity_at: project_data['last_activity_at'],
        # This is restoring a user's own previously-exported data, not a fresh
        # user submission, so the similar-title warning (meant to catch
        # accidental near-duplicates as they're typed) doesn't apply here.
        confirm_duplicate: true
      )
      project.save!
      
      # Import project statuses first
      import_project_statuses(project, project_data['statuses'] || [])
      
      # Import project tasks
      import_project_tasks(project, project_data['tasks'] || [], imported_tags)
      
      # Import project comments
      import_project_comments(project, project_data['comments'] || [])
      
      project
    end
  end
  
  def import_project_statuses(project, statuses_data)
    # Create default statuses if they don't exist
    project.create_default_statuses! if project.statuses.empty?
    
    # Import custom statuses (non-default ones)
    statuses_data.each do |status_data|
      # Skip if this is a default status (it should already exist)
      next if Status.default_statuses.values.include?(status_data['name'])
      
      # Create custom status if it doesn't exist
      unless project.statuses.exists?(name: status_data['name'])
        project.statuses.create!(
          name: status_data['name'],
          created_at: status_data['created_at'],
          updated_at: status_data['updated_at']
        )
      end
    end
  end
  
  def import_project_tasks(project, tasks_data, imported_tags)
    tasks_data.each do |task_data|
      task = project.tasks.find_or_initialize_by(title: task_data['title'])
      
      # Map status by name instead of ID
      status = nil
      if task_data['status_name'].present?
        status = project.statuses.find_by(name: task_data['status_name'])
        # If status doesn't exist, use default "Not Started"
        status ||= project.status_by_key(:not_started)
      else
        status = project.status_by_key(:not_started)
      end
      
      task.assign_attributes(
        # The export doesn't carry a per-task owner (only completed_by/
        # archived_by, which are plain historical ids, not the required
        # Task#user association) - importing is always restoring the
        # importing user's own data, so they're also every task's owner.
        user: @user,
        description: task_data['description'],
        priority: task_data['priority'],
        due_date: task_data['due_date'],
        estimated_minutes: task_data['estimated_minutes'],
        scheduled_at: task_data['scheduled_at'],
        completed: task_data['completed'],
        completed_at: task_data['completed_at'],
        archived: task_data['archived'],
        archived_at: task_data['archived_at'],
        created_at: task_data['created_at'],
        updated_at: task_data['updated_at'],
        status: status,
        # This is restoring a user's own previously-exported data, not a fresh
        # user submission, so the similar-title warning would otherwise wrongly
        # flag legitimate sibling tasks (e.g. recurring-task instances, whose
        # titles intentionally differ only by date label - see
        # RecurringTaskTemplate#generate_task_for_period!, which bypasses the
        # same check for the same reason).
        skip_duplicate_check: true
      )
      
      # Handle completed_by and archived_by - only set if the user exists
      if task_data['completed_by'].present?
        completed_by_user = User.find_by(id: task_data['completed_by'])
        task.completed_by = completed_by_user&.id
      end
      
      if task_data['archived_by'].present?
        archived_by_user = User.find_by(id: task_data['archived_by'])
        task.archived_by = archived_by_user&.id
      end
      
      task.save!
      
      # Import task comments
      import_task_comments(task, task_data['comments'] || [])
      
      # Import task tags
      import_task_tags(task, task_data['tags'] || [], imported_tags)
    end
  end
  
  def import_task_comments(task, comments_data)
    comments_data.each do |comment_data|
      # Use a more reliable identifier - combination of content and created_at
      comment = task.comments.find_or_initialize_by(
        content: comment_data['content'],
        created_at: comment_data['created_at']
      )
      comment.assign_attributes(
        user: @user,
        status: comment_data['status'],
        updated_at: comment_data['updated_at']
      )
      comment.save!
    end
  end

  def import_project_comments(project, comments_data)
    comments_data.each do |comment_data|
      # Use a more reliable identifier - combination of content and created_at
      comment = project.comments.find_or_initialize_by(
        content: comment_data['content'],
        created_at: comment_data['created_at']
      )
      comment.assign_attributes(
        user: @user,
        status: comment_data['status'],
        updated_at: comment_data['updated_at']
      )
      comment.save!
    end
  end
  
  def import_task_tags(task, tags_data, imported_tags)
    tags_data.each do |tag_data|
      tag = imported_tags.find { |t| t.name == tag_data['name'] }
      if tag && !task.tags.include?(tag)
        task.tags << tag
      end
    end
  end
  
  def encrypt_data(data, password)
    cipher = OpenSSL::Cipher.new('AES-256-CBC')
    cipher.encrypt
    cipher.key = Digest::SHA256.digest(password)
    cipher.iv = cipher.random_iv
    
    encrypted = cipher.update(data) + cipher.final
    cipher.iv + encrypted
  end
  
  def decrypt_data(encrypted_data, password)
    cipher = OpenSSL::Cipher.new('AES-256-CBC')
    cipher.decrypt
    cipher.key = Digest::SHA256.digest(password)
    cipher.iv = encrypted_data[0, 16]
    cipher.update(encrypted_data[16..-1]) + cipher.final
  end
  
  def create_zip_file(data)
    buffer = Zip::OutputStream.write_buffer do |out|
      out.put_next_entry('user_data.enc')
      out.write(data)
    end
    buffer.string
  end
  
  def extract_from_zip(zip_data)
    Zip::InputStream.open(StringIO.new(zip_data)) do |io|
      while entry = io.get_next_entry
        if entry.name == 'user_data.enc'
          return io.read
        end
      end
    end
    raise "No encrypted data found in ZIP file"
  end
  
  def generate_filename(extension)
    timestamp = Time.current.strftime("%Y%m%d_%H%M%S")
    "mustermeister_data_#{@user.id}_#{timestamp}.#{extension}"
  end
end 