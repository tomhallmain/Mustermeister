class AddTaskInsightsExcludedProjectIdsToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :task_insights_excluded_project_ids, :integer, array: true, default: [], null: false
  end
end
