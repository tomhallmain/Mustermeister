class Task < ApplicationRecord
  # Enable version tracking
  has_paper_trail versions: {
    scope: -> { order("id desc") }
  },
  meta: {
    user_id: :user_id_for_paper_trail,
    ip: :ip_for_paper_trail,
    user_agent: :user_agent_for_paper_trail
  }

  belongs_to :project
  belongs_to :user
  belongs_to :archived_by_user, class_name: 'User', foreign_key: 'archived_by', optional: true
  has_and_belongs_to_many :tags
  has_many :comments, dependent: :destroy

  validates :title, presence: true
  validates :priority, inclusion: { in: %w[low medium high] }, allow_nil: true
  validate :archived_at_presence_if_archived
  
  before_create :set_defaults
  before_destroy :ensure_no_active_dependencies
  after_save :update_project_activity
  
  scope :active, -> { where(completed: false, archived: false) }
  scope :completed, -> { where(completed: true) }
  scope :archived, -> { where(archived: true) }
  scope :not_archived, -> { where(archived: false) }
  scope :overdue, -> { where('due_date < ?', Time.current) }
  scope :with_unresolved_comments, -> { 
    joins(:comments).where(comments: { status: 'open' }).distinct 
  }
  scope :completed_before, ->(date) { completed.where('completed_at < ?', date) }
  scope :not_completed, -> { where(completed: false) }
  
  # Class methods for bulk operations
  def self.bulk_update_status(ids, status, current_user)
    transaction do
      tasks = where(id: ids)
      tasks.each do |task|
        task.paper_trail_event = 'bulk_status_update'
        task.update!(completed: status)
      end
      
      # Log the bulk operation
      Rails.logger.info "Bulk status update performed by #{current_user.id} on tasks: #{ids}"
    end
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error "Bulk update failed: #{e.message}"
    raise
  end
  
  # Instance methods
  def mark_as_complete!(user)
    transaction do
      self.completed = true
      self.completed_at = Time.current
      self.completed_by = user.id
      save!
      
      # Update any dependent records
      comments.update_all(status: 'closed') if comments.exists?
      
      # Notify relevant users
      NotificationService.task_completed(self) if defined?(NotificationService)
    end
  end

  def archive!(user)
    return false if archived?
    
    transaction do
      self.paper_trail_event = 'archive'
      update!(
        archived: true,
        archived_at: Time.current,
        archived_by: user.id
      )
      
      # Close any open comments
      comments.where(status: 'open').update_all(
        status: 'closed',
        updated_at: Time.current
      )
      
      # Add an archive note
      comments.create!(
        user: user,
        content: "Task archived on #{archived_at.strftime('%Y-%m-%d')}",
        status: 'closed'
      )
    end
    true
  rescue ActiveRecord::RecordInvalid => e
    errors.add(:base, "Failed to archive task: #{e.message}")
    false
  end
  
  private
  
  def set_defaults
    self.completed ||= false
    self.priority ||= 'medium'
    self.archived ||= false
  end
  
  def ensure_no_active_dependencies
    if comments.unresolved.exists?
      errors.add(:base, "Cannot delete task with unresolved comments")
      throw :abort
    end
  end
  
  def archived_at_presence_if_archived
    if archived? && archived_at.blank?
      errors.add(:archived_at, "must be present when task is archived")
    end
  end
  
  def update_project_activity
    project.update_column(:last_activity_at, Time.current)
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
