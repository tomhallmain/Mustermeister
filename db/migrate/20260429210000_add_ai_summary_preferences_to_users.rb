class AddAiSummaryPreferencesToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :ai_summary_locale, :string
    add_column :users, :ai_summary_model, :string
  end
end
