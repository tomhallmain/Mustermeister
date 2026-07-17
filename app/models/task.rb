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
  belongs_to :task_category, optional: true
  has_one :task_result, dependent: :destroy
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
  after_save :sync_task_result_with_completion
  
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

  # I18n display methods
  def priority_display
    I18n.t("priorities.#{priority}")
  end

  def status_display
    I18n.t("statuses.#{status.name.parameterize.underscore}", default: status.name)
  end

  def result_display
    return nil unless task_result

    I18n.t("task_results.values.#{task_result.result}")
  end

  StatusChangeEntry = Struct.new(:from_status, :to_status, :changed_at, :user, :event, keyword_init: true)

  def self.localized_status_name(status)
    return I18n.t("views.tasks.show.status_history.unknown") unless status

    I18n.t("statuses.#{status.name.parameterize.underscore}", default: status.name)
  end

  def status_change_history
    chron = versions.reorder(created_at: :asc, id: :asc).to_a
    return [] if chron.empty?

    raw_entries = []
    previous_status_id = nil

    chron.each_with_index do |version, index|
      status_after = status_id_after_event(version, chron, index)
      next unless status_after

      if previous_status_id.nil?
        raw_entries << build_status_change_raw_entry(version, nil, status_after)
      elsif previous_status_id != status_after
        raw_entries << build_status_change_raw_entry(version, previous_status_id, status_after)
      end

      previous_status_id = status_after
    end

    status_ids = raw_entries.flat_map { |entry| [entry[:from_id], entry[:to_id]] }.compact.uniq
    user_ids = raw_entries.map { |entry| entry[:user_id] }.compact.uniq
    statuses_by_id = Status.where(id: status_ids).index_by(&:id)
    users_by_id = User.where(id: user_ids).index_by(&:id)

    raw_entries.map do |entry|
      StatusChangeEntry.new(
        from_status: statuses_by_id[entry[:from_id]],
        to_status: statuses_by_id[entry[:to_id]],
        changed_at: entry[:changed_at],
        user: resolve_status_change_user(entry, users_by_id),
        event: entry[:event]
      )
    end.reverse
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

  def sync_task_result_with_completion
    if completed?
      task_result || create_task_result!(result: :complete)
    elsif task_result
      task_result.destroy!
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

  def build_status_change_raw_entry(version, from_id, to_id)
    {
      from_id: from_id,
      to_id: to_id,
      changed_at: version.created_at,
      user_id: version_user_id(version),
      event: version.event,
      version: version
    }
  end

  def resolve_status_change_user(entry, users_by_id)
    user_id = entry[:user_id]
    return users_by_id[user_id] if user_id && users_by_id[user_id]

    user if entry[:event] == "create"
  end

  # Status after this version was applied. The next version's `object` snapshot is the
  # pre-update state for that later change, i.e. the post-change state for this one.
  def status_id_after_event(version, chron, index)
    next_version = chron[index + 1]
    if next_version&.object.present?
      status_id_from_serialized_object(next_version.object)
    else
      status_id
    end
  end

  def version_user_id(version)
    id = version.user_id.presence || version.whodunnit.presence
    id.present? ? id.to_i : nil
  end

  def status_id_from_serialized_object(serialized)
    data = PaperTrail.serializer.load(serialized)
    data["status_id"] || data[:status_id]
  rescue StandardError
    nil
  end
end
