class CreateRecurringTaskTemplates < ActiveRecord::Migration[8.0]
  def change
    create_table :recurring_task_templates do |t|
      t.string :title, null: false
      t.text :description
      t.references :project, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :priority, default: "medium"
      t.references :task_category, null: true, foreign_key: true
      t.string :frequency, null: false
      t.date :start_date, null: false
      t.boolean :active, null: false, default: true
      t.datetime :paused_at
      t.date :last_generated_period_start

      t.timestamps
    end

    add_index :recurring_task_templates, :active
  end
end
