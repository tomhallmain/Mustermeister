class CreateStatuses < ActiveRecord::Migration[8.0]
  def change
    create_table :statuses do |t|
      t.string :name, null: false
      t.references :project, null: false, foreign_key: true

      t.timestamps
    end

    add_index :statuses, [:project_id, :name], unique: true

    # Create default statuses for existing projects
    reversible do |dir|
      dir.up do
        # Use raw SQL to avoid model loading issues
        safety_assured do
          execute <<-SQL
            INSERT INTO statuses (name, project_id, created_at, updated_at)
            SELECT 
              unnest(ARRAY['Not Started', 'To Investigate', 'Investigated / Not Started', 'In Progress', 'Ready to Test', 'Closed', 'Complete']),
              id,
              NOW(),
              NOW()
            FROM projects;
          SQL
        end
      end
    end
  end
end
