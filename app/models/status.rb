class Status < ApplicationRecord
  belongs_to :project
  has_many :tasks

  validates :name, presence: true
  validates :name, uniqueness: { scope: :project_id }

  before_validation :assign_position, on: :create

  scope :ordered, -> { order(:position, :id) }
  scope :custom, -> { where.not(name: Status.default_statuses.values) }

  # Default statuses as class methods
  def self.default_statuses
    {
      not_started: 'Not Started',
      to_investigate: 'To Investigate',
      investigated: 'Investigated',
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

  def in_use?
    tasks.exists?
  end

  # Swaps position with the previous status (by position, id) in the same
  # project. No-op at the start of the list.
  def move_earlier
    swap_position_with(project.statuses.ordered.where('position < ?', position).last)
  end

  # Swaps position with the next status (by position, id) in the same
  # project. No-op at the end of the list.
  def move_later
    swap_position_with(project.statuses.ordered.where('position > ?', position).first)
  end

  private

  def assign_position
    return if position.present?
    return unless project

    self.position = (project.statuses.maximum(:position) || -1) + 1
  end

  def swap_position_with(other)
    return false unless other

    Status.transaction do
      my_position = position
      update!(position: other.position)
      other.update!(position: my_position)
    end

    true
  end
end
