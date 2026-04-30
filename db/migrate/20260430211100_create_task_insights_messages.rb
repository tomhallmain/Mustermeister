class CreateTaskInsightsMessages < ActiveRecord::Migration[8.0]
  def change
    create_table :task_insights_messages do |t|
      t.references :task_insights_conversation, null: false, foreign_key: true, index: { name: "index_task_insights_messages_on_conversation_id" }
      t.string :role, null: false
      t.text :content, null: false
      t.jsonb :tool_calls, null: false, default: []
      t.jsonb :state_events, null: false, default: []

      t.timestamps
    end

    add_index :task_insights_messages, [:task_insights_conversation_id, :created_at], name: "index_task_insights_messages_on_conversation_and_created_at"
  end
end
