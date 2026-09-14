class CreateProjectMemberships < ActiveRecord::Migration[8.0]
  def change
    create_table :project_memberships do |t|
      t.references :project, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :role, null: false, default: "member"

      t.timestamps
    end

    # The owner's access comes from projects.user_id, so no membership row
    # exists for them and every project starts with an empty members list.
    add_index :project_memberships, [:project_id, :user_id], unique: true
  end
end
