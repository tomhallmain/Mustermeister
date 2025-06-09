class AddForeignKeyToTasksStatus < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def up
    safety_assured do
      # Set default status for existing tasks
      execute <<-SQL
        UPDATE tasks
        SET status_id = (
          SELECT id
          FROM statuses
          WHERE statuses.project_id = tasks.project_id
          AND statuses.name = 'Not Started'
          LIMIT 1
        )
        WHERE status_id IS NULL;
      SQL

      # Make status required
      change_column_null :tasks, :status_id, false

      # Add foreign key
      add_foreign_key :tasks, :statuses, validate: false
      validate_foreign_key :tasks, :statuses
    end
  end

  def down
    remove_foreign_key :tasks, :statuses
    change_column_null :tasks, :status_id, true
  end
end 