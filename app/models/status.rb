class Status < ApplicationRecord
  belongs_to :project
  has_many :tasks

  validates :name, presence: true
  validates :name, uniqueness: { scope: :project_id }
  
  # Default statuses as class methods
  def self.default_statuses
    {
      not_started: 'Not Started',
      to_investigate: 'To Investigate',
      investigated_not_started: 'Investigated / Not Started',
      in_progress: 'In Progress',
      ready_to_test: 'Ready to Test',
      closed: 'Closed',
      complete: 'Complete'
    }
  end

  # Helper method to check if a status is a default one
  def default?
    self.class.default_statuses.values.include?(name)
  end

  # Helper method to get the default status key
  def default_key
    self.class.default_statuses.key(name)
  end
end
