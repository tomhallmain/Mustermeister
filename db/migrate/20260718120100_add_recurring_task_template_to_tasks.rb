class AddRecurringTaskTemplateToTasks < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    add_reference :tasks, :recurring_task_template, null: true, index: { algorithm: :concurrently }

    safety_assured do
      add_foreign_key :tasks, :recurring_task_templates, validate: false
      validate_foreign_key :tasks, :recurring_task_templates
    end
  end
end
