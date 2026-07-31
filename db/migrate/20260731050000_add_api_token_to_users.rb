class AddApiTokenToUsers < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    add_column :users, :api_token, :string
    add_index :users, :api_token, unique: true, algorithm: :concurrently
  end
end
