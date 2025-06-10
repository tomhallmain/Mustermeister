class Project < ApplicationRecord
  # Enable version tracking with metadata
  has_paper_trail versions: {
    scope: -> { order("id desc") }
  },
  meta: {
    user_id: :user_id_for_paper_trail,
    ip: :ip_for_paper_trail,
    user_agent: :user_agent_for_paper_trail
  }
  
  has_many :tasks, dependent: :destroy
  has_many :comments, dependent: :destroy
  has_many :statuses, dependent: :destroy
  belongs_to :user

  validates :title, presence: true
  validates :default_priority, inclusion: { in: %w[low medium high leisure] }, allow_nil: true
  
  before_save :update_last_activity
  before_create :set_initial_activity
  after_create :create_default_statuses
  
  scope :not_completed, -> { 
    joins(:tasks)
      .where(tasks: { completed: false })
      .distinct
  }
  
  def completion_percentage
    return 0 if tasks.empty?
    ((tasks.where(completed: true).count.to_f / tasks.count) * 100).round
  end

  def status
    return 'not_started' if tasks.empty?
    return 'completed' if completion_percentage == 100
    return 'in_progress' if completion_percentage > 0
    'not_started'
  end

  # Helper method to find a status by its default key
  def status_by_key(key)
    statuses.find_by(name: Status.default_statuses[key])
  end

  # Helper method to create a task with default status
  def create_task!(attributes = {})
    tasks.create!(attributes.merge(status: status_by_key(:not_started)))
  end

  # Helper method to build a task with default status
  def build_task(attributes = {})
    tasks.build(attributes.merge(status: status_by_key(:not_started)))
  end

  # Public method to create default statuses
  def create_default_statuses!
    return if statuses.any?  # Don't recreate if statuses already exist
    Status.default_statuses.each do |key, name|
      statuses.create!(name: name)
    end
  end

  private

  def set_initial_activity
    self.last_activity_at = Time.current
  end

  def update_last_activity
    self.last_activity_at = Time.current
  end

  def create_default_statuses
    Status.default_statuses.each do |key, name|
      statuses.create!(name: name)
    end
  end

  # PaperTrail metadata methods
  def user_id_for_paper_trail
    PaperTrail.request.whodunnit
  end
  
  def ip_for_paper_trail
    PaperTrail.request.controller_info[:ip]
  end
  
  def user_agent_for_paper_trail
    PaperTrail.request.controller_info[:user_agent]
  end
end
