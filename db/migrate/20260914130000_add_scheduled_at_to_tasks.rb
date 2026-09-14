class AddScheduledAtToTasks < ActiveRecord::Migration[8.0]
  def change
    add_column :tasks, :scheduled_at, :datetime
  end
end
