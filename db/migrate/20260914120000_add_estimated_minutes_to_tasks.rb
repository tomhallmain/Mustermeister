class AddEstimatedMinutesToTasks < ActiveRecord::Migration[8.0]
  def change
    add_column :tasks, :estimated_minutes, :integer
  end
end
