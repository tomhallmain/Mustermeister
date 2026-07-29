class AddDefaultCategoryToProjects < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    add_reference :projects, :default_category, null: true, index: { algorithm: :concurrently }

    safety_assured do
      add_foreign_key :projects, :task_categories, column: :default_category_id, validate: false
      validate_foreign_key :projects, :task_categories, column: :default_category_id
    end
  end
end
