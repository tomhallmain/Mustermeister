class CreateTaskCategories < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    create_table :task_categories do |t|
      t.string :name, null: false
      t.references :user, null: true, foreign_key: true

      t.timestamps
    end

    add_index :task_categories, [:user_id, :name], unique: true

    add_reference :tasks, :task_category, null: true, index: { algorithm: :concurrently }

    safety_assured do
      add_foreign_key :tasks, :task_categories, validate: false
      validate_foreign_key :tasks, :task_categories
    end
  end
end
