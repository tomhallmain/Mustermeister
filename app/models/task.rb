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
  belongs_to :status
  has_and_belongs_to_many :tags
  has_many :comments, dependent: :destroy

  validates :title, presence: true
  validates :priority, inclusion: { in: %w[low medium high leisure] }, allow_nil: true
  validate :archived_at_presence_if_archived
  validate :status_belongs_to_project
  
  before_validation :set_defaults
  before_destroy :ensure_no_active_dependencies
  after_save :update_project_activity
  after_save :handle_status_completion
  
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
  
  # Status helper methods
  def not_started?
    status.name == Status.default_statuses[:not_started]
  end

  def to_investigate?
    status.name == Status.default_statuses[:to_investigate]
  end

  def investigated?
    status.name == Status.default_statuses[:investigated]
  end

  def in_progress?
    status.name == Status.default_statuses[:in_progress]
  end

  def ready_to_test?
    status.name == Status.default_statuses[:ready_to_test]
  end

  def closed?
    status.name == Status.default_statuses[:closed]
  end

  def complete?
    status.name == Status.default_statuses[:complete]
  end

  # Class methods for bulk operations
  def self.bulk_update_status(ids, status_id, current_user)
    transaction do
      tasks = where(id: ids)
      tasks.each do |task|
        task.paper_trail_event = 'bulk_status_update'
        task.update!(status_id: status_id)
      end
      
      # Log the bulk operation
      Rails.logger.info "Bulk status update performed by #{current_user.id} on tasks: #{ids}"
    end
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error "Bulk update failed: #{e.message}"
    raise
  end
  
  # Instance methods
  def mark_as_complete!(user_or_id)
    transaction do
      self.completed = true
      self.completed_at = Time.current
      self.completed_by = user_or_id.is_a?(User) ? user_or_id.id : user_or_id
      self.status = project.status_by_key(:complete)
      save!
      
      # Update any dependent records
      comments.update_all(status: 'closed') if comments.exists?
      
      # Notify relevant users
      NotificationService.task_completed(self) if defined?(NotificationService)
    end
  end

  def mark_as_incomplete!
    transaction do
      self.completed = false
      self.completed_at = nil
      self.completed_by = nil
      save!
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
  
  def status_name=(name)
    return unless name.present? && project
    self.status = project.statuses.find_by(name: name)
  end
  
  private
  
  def set_defaults
    self.completed ||= false
    self.priority ||= project&.default_priority || 'medium'
    self.archived ||= false
    self.status ||= project&.status_by_key(:not_started)
  end
  
  def handle_status_completion
    if saved_change_to_status_id?
      # Ignore changes if current status is 'Closed'
      return if status.name == Status.default_statuses[:closed]
      
      if status.name == Status.default_statuses[:complete]
        mark_as_complete!(PaperTrail.request.whodunnit)
      elsif status.name_was == Status.default_statuses[:complete]
        mark_as_incomplete!
      end
    end
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

  def status_belongs_to_project
    if status && project && status.project_id != project_id
      errors.add(:status, "must belong to the same project")
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
