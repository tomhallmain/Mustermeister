class UpdateCompletedTasksStatus < ActiveRecord::Migration[8.0]
  def up
    # For each project, find or create the required statuses
    Project.find_each do |project|
      complete_status = project.statuses.find_or_create_by!(
        name: Status.default_statuses[:complete]
      )
      not_started_status = project.statuses.find_or_create_by!(
        name: Status.default_statuses[:not_started]
      )

      # Update completed tasks to have Complete status
      Task.where(project: project, completed: true)
          .update_all(status_id: complete_status.id)

      # Update incomplete tasks to have Not Started status
      Task.where(project: project, completed: false)
          .update_all(status_id: not_started_status.id)
    end
  end

  def down
    # No need to revert this data migration
  end
end
