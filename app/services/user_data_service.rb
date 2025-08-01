require 'zip'
require 'openssl'

class UserDataService
  SUPPORTED_FORMATS = %w[json encrypted_zip].freeze
  
  class << self
    def export_data(user, format: 'json', password: nil)
      new(user).export_data(format, password)
    end
    
    def import_data(user, file, password: nil)
      new(user).import_data(file, password)
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
  
  def import_data(file, password = nil)
    begin
      file_extension = File.extname(file.original_filename).downcase
      
      case file_extension
      when '.json'
        import_json(file)
      when '.zip'
        import_encrypted_zip(file, password)
      else
        { success: false, error: "Unsupported file format. Please use .json or .zip files." }
      end
    rescue => e
      { success: false, error: "Import failed: #{e.message}" }
    end
  end
  
  def validate_import_file(file)
    return { valid: false, error: "No file provided" } unless file
    
    file_extension = File.extname(file.original_filename).downcase
    max_size = 50.megabytes # 50MB limit
    
    if file.size > max_size
      return { valid: false, error: "File too large. Maximum size is #{max_size / 1.megabyte}MB" }
    end
    
    unless ['.json', '.zip'].include?(file_extension)
      return { valid: false, error: "Unsupported file format. Please use .json or .zip files." }
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
  
  def import_json(file)
    json_content = file.read
    data = JSON.parse(json_content)
    
    import_user_data(data)
  end
  
  def import_encrypted_zip(file, password)
    # Extract ZIP file
    zip_content = file.read
    encrypted_data = extract_from_zip(zip_content)
    
    # Decrypt the data
    compressed_data = decrypt_data(encrypted_data, password)
    
    # Decompress the data
    json_data = Zlib::Inflate.inflate(compressed_data)
    
    # Parse JSON
    data = JSON.parse(json_data)
    
    import_user_data(data)
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
      standalone_tasks: @user.tasks.where(project: nil).map do |task|
        {
          id: task.id,
          title: task.title,
          description: task.description,
          priority: task.priority,
          due_date: task.due_date,
          completed: task.completed,
          completed_at: task.completed_at,
          completed_by: task.completed_by,
          archived: task.archived,
          archived_at: task.archived_at,
          created_at: task.created_at,
          updated_at: task.updated_at,
          status_name: task.status&.name, # Export status name instead of ID, handle nil case
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
  
  def import_user_data(data)
    ActiveRecord::Base.transaction do
      # Validate data structure
      unless data['export_info'] && data['user']
        raise "Invalid data format. Missing required export information."
      end
      
      # Import tags first (they might be referenced by tasks)
      imported_tags = import_tags(data['tags'] || [])
      
      # Import projects and their tasks
      imported_projects = import_projects(data['projects'] || [], imported_tags)
      
      # Import standalone tasks
      imported_standalone_tasks = import_standalone_tasks(data['standalone_tasks'] || [], imported_tags)
      
      {
        success: true,
        imported: {
          projects: imported_projects.count,
          tasks: imported_projects.sum { |p| p.tasks.count } + imported_standalone_tasks.count,
          tags: imported_tags.count,
          comments: imported_projects.sum { |p| p.comments.count } + 
                   imported_projects.sum { |p| p.tasks.sum { |t| t.comments.count } } +
                   imported_standalone_tasks.sum { |t| t.comments.count }
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
        last_activity_at: project_data['last_activity_at']
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
        description: task_data['description'],
        priority: task_data['priority'],
        due_date: task_data['due_date'],
        completed: task_data['completed'],
        completed_at: task_data['completed_at'],
        archived: task_data['archived'],
        archived_at: task_data['archived_at'],
        created_at: task_data['created_at'],
        updated_at: task_data['updated_at'],
        status: status
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
  
  def import_standalone_tasks(tasks_data, imported_tags)
    tasks_data.map do |task_data|
      task = @user.tasks.find_or_initialize_by(title: task_data['title'], project: nil)
      
      # For standalone tasks, we need to handle status differently
      # Since they don't belong to a project, we'll skip status assignment
      # or create a default status if needed
      
      task.assign_attributes(
        description: task_data['description'],
        priority: task_data['priority'],
        due_date: task_data['due_date'],
        completed: task_data['completed'],
        completed_at: task_data['completed_at'],
        archived: task_data['archived'],
        archived_at: task_data['archived_at'],
        created_at: task_data['created_at'],
        updated_at: task_data['updated_at']
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
      
      # For standalone tasks, we need to handle the status requirement
      # Since statuses belong to projects, we'll try to find a suitable status
      # or create a temporary one if needed
      if task_data['status_name'].present?
        # Try to find a status with this name from any of the user's projects
        status = @user.projects.joins(:statuses)
                      .where(statuses: { name: task_data['status_name'] })
                      .first&.statuses&.find_by(name: task_data['status_name'])
        
        if status
          task.status = status
        else
          # If no matching status found, use the first available status from any project
          first_status = @user.projects.joins(:statuses).first&.statuses&.first
          task.status = first_status if first_status
        end
      else
        # Use the first available status from any project
        first_status = @user.projects.joins(:statuses).first&.statuses&.first
        task.status = first_status if first_status
      end
      
      # If we still don't have a status, we need to handle this case
      # This might indicate a data integrity issue in the current system
      unless task.status
        Rails.logger.warn "Standalone task '#{task.title}' has no valid status. This may indicate a data integrity issue."
        # Try to create a minimal status for this task
        # This is a workaround for the current system limitation
        begin
          # Create a temporary project with default statuses just for this task
          temp_project = @user.projects.create!(
            title: "Temporary Project for Standalone Task",
            description: "Auto-created for data import"
          )
          temp_project.create_default_statuses!
          task.status = temp_project.status_by_key(:not_started)
          task.project = temp_project  # Assign to the temporary project
        rescue => e
          Rails.logger.error "Failed to create temporary project for standalone task: #{e.message}"
          raise "Cannot import standalone task '#{task.title}': No valid status available"
        end
      end
      
      task.save!
      
      # Import task comments
      import_task_comments(task, task_data['comments'] || [])
      
      # Import task tags
      import_task_tags(task, task_data['tags'] || [], imported_tags)
      
      task
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