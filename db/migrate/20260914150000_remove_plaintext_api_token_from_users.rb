class RemovePlaintextApiTokenFromUsers < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def up
    add_index :users, :api_token_digest, unique: true, algorithm: :concurrently

    # Kept apart from the additive migration so the drop can be deployed on
    # its own: dropping a column while an instance still running older code
    # selects it raises "column users.api_token does not exist". The preceding
    # migration leaves the app fully working with this column still present,
    # so deploy that plus the digest-based code first where instances overlap.
    safety_assured { remove_column :users, :api_token }
  end

  # Restores the column and its index but not a single token value - a digest
  # cannot be turned back into the token it came from. Every API client would
  # need a freshly generated token after a rollback.
  def down
    add_column :users, :api_token, :string
    add_index :users, :api_token, unique: true, algorithm: :concurrently
    remove_index :users, :api_token_digest, algorithm: :concurrently
  end
end
