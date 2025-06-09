class RenameInvestigatedNotStartedToInvestigated < ActiveRecord::Migration[8.0]
  def up
    # Update all statuses with the old name to the new name
    Status.where(name: 'Investigated / Not Started').update_all(name: 'Investigated')
  end

  def down
    # Revert back to the old name if needed
    Status.where(name: 'Investigated').update_all(name: 'Investigated / Not Started')
  end
end
