class CreateAttachments < ActiveRecord::Migration[8.0]
  def change
    create_table :attachments do |t|
      t.references :task, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.jsonb :file_data, null: false

      t.timestamps
    end

    create_table :attachment_blobs do |t|
      t.string :blob_id, null: false
      t.binary :data, null: false

      t.timestamps
    end
    add_index :attachment_blobs, :blob_id, unique: true
  end
end
