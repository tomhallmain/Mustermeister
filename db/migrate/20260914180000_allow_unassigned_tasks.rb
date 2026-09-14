class AllowUnassignedTasks < ActiveRecord::Migration[8.0]
  # "Unassigned" needs to be representable before a task can be handed between
  # collaborators: removing someone from a project has to leave their tasks
  # somewhere, and handing them to the project owner would be a silent
  # reassignment nobody asked for. Creator attribution is unaffected - that
  # lives in created_by.
  def up
    change_column_null :tasks, :user_id, true
  end

  def down
    execute <<~SQL.squish
      UPDATE tasks SET user_id = created_by WHERE user_id IS NULL AND created_by IS NOT NULL
    SQL
    change_column_null :tasks, :user_id, false
  end
end
