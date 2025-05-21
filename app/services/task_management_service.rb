class TaskManagementService
  class Error < StandardError; end
  
  def self.transfer_tasks(from_user:, to_user:, notify: true)
    ApplicationRecord.transaction do
      tasks = Task.where(user_id: from_user.id)
      
      # Track the transfer in versions
      tasks.find_each do |task|
        task.paper_trail_event = 'transfer_ownership'
        task.update!(
          user: to_user,
          updated_at: Time.current
        )
      end
      
      # Update any in-progress comments
      Comment.where(task_id: tasks.select(:id))
             .where(status: 'open')
             .update_all(user_id: to_user.id)
      
      if notify && defined?(NotificationService)
        NotificationService.task_transfer_completed(
          from_user: from_user,
          to_user: to_user,
          task_count: tasks.count
        )
      end
      
      return tasks.count
    end
  rescue ActiveRecord::RecordInvalid => e
    raise Error, "Failed to transfer tasks: #{e.message}"
  end
  
  def self.bulk_reschedule(task_ids:, new_due_date:, current_user:)
    return 0 if task_ids.blank?

    new_due_date = new_due_date.to_date
    
    # Validate the new due date
    if new_due_date < Date.current
      raise Error, "Cannot set due date in the past"
    end
    
    ApplicationRecord.transaction do
      tasks = Task.where(id: task_ids)
                 .not_archived
                 .includes(:comments)
      
      # Track the update in versions
      tasks.find_each do |task|
        task.paper_trail_event = 'bulk_reschedule'
        task.update!(
          due_date: new_due_date,
          updated_at: Time.current
        )
        
        # Create an audit comment
        task.comments.create!(
          user: current_user,
          content: "Due date changed to #{new_due_date.strftime('%Y-%m-%d')}",
          status: 'resolved'
        )
      end
      
      return tasks.count
    end
  rescue ActiveRecord::RecordInvalid => e
    raise Error, "Failed to reschedule tasks: #{e.message}"
  end
  
  def self.archive_completed_tasks(before_date:, current_user:)
    before_date = before_date.to_date
    
    ApplicationRecord.transaction do
      tasks = Task.where(completed: true)
                 .where('completed_at < ?', before_date)
                 .not_archived
      
      archived_count = 0
      
      tasks.find_each do |task|
        # Archive the task (you'd need to add an archived column or status)
        task.paper_trail_event = 'archive'
        task.update!(
          archived: true,
          archived_at: Time.current,
          archived_by: current_user.id
        )
        
        # Close any open comments
        task.comments.where(status: 'open')
             .update_all(status: 'closed')
        
        archived_count += 1
      end
      
      # Log the archival operation
      Rails.logger.info "Archived #{archived_count} tasks completed before #{before_date}"
      
      return archived_count
    end
  rescue ActiveRecord::RecordInvalid => e
    raise Error, "Failed to archive tasks: #{e.message}"
  end

  def self.reschedule_project_tasks(project:, old_due_date:, new_due_date:, current_user:)
    return 0 if old_due_date.nil? || new_due_date.nil?

    old_due_date = old_due_date.to_date
    new_due_date = new_due_date.to_date
    
    # Calculate the number of days to shift
    days_shift = (new_due_date - old_due_date).to_i
    
    ApplicationRecord.transaction do
      tasks = project.tasks.not_archived.includes(:comments)
      updated_count = 0
      
      tasks.find_each do |task|
        next unless task.due_date # Skip tasks without due dates

        # Calculate new due date maintaining relative timing
        task_days_before_project_end = (old_due_date - task.due_date).to_i
        new_task_due_date = new_due_date - task_days_before_project_end
        
        task.paper_trail_event = 'project_reschedule'
        task.update!(
          due_date: new_task_due_date,
          updated_at: Time.current
        )
        
        # Create an audit comment
        task.comments.create!(
          user: current_user,
          content: "Due date adjusted by #{days_shift} days due to project reschedule",
          status: 'resolved'
        )
        
        updated_count += 1
      end
      
      if updated_count > 0 && defined?(NotificationService)
        NotificationService.project_reschedule_completed(
          project: project,
          days_shifted: days_shift,
          tasks_updated: updated_count,
          user: current_user
        )
      end
      
      return updated_count
    end
  rescue ActiveRecord::RecordInvalid => e
    raise Error, "Failed to reschedule project tasks: #{e.message}"
  end

  def self.reprioritize_project_tasks(project:, current_user:)
    raise Error, "Project cannot be nil" if project.nil?
    return 0 if project.default_priority.nil?

    ApplicationRecord.transaction do
      tasks = project.tasks.not_archived.includes(:comments)
      updated_count = 0
      
      tasks.find_each do |task|
        next if task.priority == project.default_priority # Skip tasks that already match

        task.paper_trail_event = 'project_reprioritize'
        task.update!(
          priority: project.default_priority,
          updated_at: Time.current
        )
        
        # Create an audit comment
        Comment.create!(
          task: task,
          user: current_user,
          content: "Priority updated to #{project.default_priority} to match project default",
          status: 'resolved'
        )
        
        updated_count += 1
      end
      
      if updated_count > 0 && defined?(NotificationService)
        NotificationService.project_reprioritize_completed(
          project: project,
          tasks_updated: updated_count,
          user: current_user
        )
      end
      
      return updated_count
    end
  rescue ActiveRecord::RecordInvalid => e
    raise Error, "Failed to reprioritize project tasks: #{e.message}"
  end
end 