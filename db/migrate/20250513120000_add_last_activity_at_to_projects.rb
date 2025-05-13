class AddLastActivityAtToProjects < ActiveRecord::Migration[8.0]
  def up
    add_column :projects, :last_activity_at, :datetime
    
    # Set initial values based on the most recent activity
    Project.find_each do |project|
      last_task_update = project.tasks.maximum(:updated_at)
      last_project_update = project.updated_at
      
      project.update_column(
        :last_activity_at,
        [last_task_update, last_project_update].compact.max
      )
    end
  end

  def down
    remove_column :projects, :last_activity_at
  end
end 