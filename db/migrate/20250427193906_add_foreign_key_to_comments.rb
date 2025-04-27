class AddForeignKeyToComments < ActiveRecord::Migration[8.0]
  def change
    add_foreign_key :comments, :projects, validate: false
  end
end
