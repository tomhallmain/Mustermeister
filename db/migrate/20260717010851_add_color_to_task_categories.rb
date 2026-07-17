class AddColorToTaskCategories < ActiveRecord::Migration[8.0]
  def change
    add_column :task_categories, :color, :string
  end
end
