class AddStatusToTasks < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    add_reference :tasks, :status, index: {algorithm: :concurrently}
  end
end
