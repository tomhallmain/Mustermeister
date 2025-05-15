class AddDefaultPriorityToProjects < ActiveRecord::Migration[8.0]
  def change
    add_column :projects, :default_priority, :string, default: 'medium'
  end
end 