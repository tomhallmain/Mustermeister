class AddCreatedByToTasks < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def up
    add_column :tasks, :created_by, :integer

    # user_id means "whoever created it" up to this point, so it is the correct
    # historical creator for every existing row. Backfilling now preserves that
    # attribution before multi-user assignment repurposes user_id into
    # "assignee", after which it can no longer be recovered.
    safety_assured do
      execute <<~SQL.squish
        UPDATE tasks SET created_by = user_id WHERE created_by IS NULL
      SQL
    end

    add_index :tasks, :created_by, algorithm: :concurrently

    safety_assured do
      add_foreign_key :tasks, :users, column: :created_by, validate: false
      validate_foreign_key :tasks, :users, column: :created_by
    end
  end

  def down
    remove_foreign_key :tasks, :users, column: :created_by
    remove_column :tasks, :created_by
  end
end
