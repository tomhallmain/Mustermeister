class AddApiTokenDigestToUsers < ActiveRecord::Migration[8.0]
  def up
    add_column :users, :api_token_digest, :string
    add_column :users, :api_token_scope, :string, null: false, default: "read"

    # Tokens already in use keep working: the digest is derived from the
    # plaintext column, which is still present at this point and is dropped
    # by the following migration. Every migrated token lands on the "read"
    # default, so none of them gains write access from this change alone.
    # Requires PostgreSQL 11+ for sha256().
    safety_assured do
      execute <<~SQL.squish
        UPDATE users
        SET api_token_digest = encode(sha256(convert_to(api_token, 'UTF8')), 'hex')
        WHERE api_token IS NOT NULL
      SQL
    end
  end

  def down
    remove_column :users, :api_token_scope
    remove_column :users, :api_token_digest
  end
end
