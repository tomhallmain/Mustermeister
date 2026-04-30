class CreateTaskInsightsConversations < ActiveRecord::Migration[8.0]
  def change
    create_table :task_insights_conversations do |t|
      t.references :user, null: false, foreign_key: true
      t.string :title, null: false
      t.datetime :last_message_at, null: false

      t.timestamps
    end

    add_index :task_insights_conversations, [:user_id, :last_message_at]
  end
end
