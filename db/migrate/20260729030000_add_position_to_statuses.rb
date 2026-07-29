class AddPositionToStatuses < ActiveRecord::Migration[8.0]
  def up
    add_column :statuses, :position, :integer

    safety_assured do
      execute <<-SQL
        UPDATE statuses
        SET position = ordered.position
        FROM (
          SELECT id, ROW_NUMBER() OVER (PARTITION BY project_id ORDER BY id) - 1 AS position
          FROM statuses
        ) AS ordered
        WHERE statuses.id = ordered.id;
      SQL

      change_column_null :statuses, :position, false
    end
  end

  def down
    remove_column :statuses, :position
  end
end
