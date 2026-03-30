class CreateTaskResults < ActiveRecord::Migration[8.0]
  def change
    create_table :task_results do |t|
      t.references :task, null: false, foreign_key: true, index: { unique: true }
      t.integer :result, null: false, default: 0
      t.string :result_reason

      t.timestamps
    end
  end
end
