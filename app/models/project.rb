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
  has_many :recurring_task_templates, dependent: :destroy
  belongs_to :user

  # Not persisted - lets the create/edit form warn on a likely-duplicate
  # title without hard-blocking: set to a truthy value to bypass the check
  # on a resubmit ("Save Anyway").
  attr_accessor :confirm_duplicate

  # Process-wide escape hatch for the duplicate-title check, meant only for
  # test setup that creates bulk/placeholder records incidentally similar to
  # each other - see ActiveSupport::TestCase#without_duplicate_title_check.
  class_attribute :duplicate_title_check_disabled, default: false

  validates :title, presence: true
  validates :default_priority, inclusion: { in: %w[low medium high leisure] }, allow_nil: true
  validates :color, inclusion: { in: %w[red orange yellow green blue purple pink gray], message: "must be a valid color" }, allow_nil: true, allow_blank: true
  validate :warn_if_similar_title_exists, on: %i[create update]

  before_save :update_last_activity
  before_create :set_initial_activity
  after_create :create_default_statuses
  # confirm_duplicate is meant to authorize exactly one save - an
  # attr_accessor otherwise has no reason to clear itself, so without this a
  # record saved twice in-process (a console session, a job, tests) would
  # silently keep bypassing the check after the first legitimate use.
  after_save :reset_duplicate_confirmation

  scope :not_completed, -> {
    joins(:tasks)
      .where(tasks: { completed: false })
      .distinct
  }

  # Orders projects by the update time of their most recently updated ACTIVE
  # (not completed, not archived) task, falling back to the project's own
  # updated_at when it has no active tasks. The active condition lives in the
  # JOIN itself (not a WHERE clause) so a project with only completed/archived
  # tasks still gets a row here (with null task columns) and correctly falls
  # back, rather than being dropped from the result entirely. Deliberately
  # excludes completed/archived tasks so that bulk-archiving old, already-done
  # tasks (see TaskManagementService.archive_completed_tasks) doesn't bump a
  # dormant project to the top just because one of its old tasks got touched.
  scope :ordered_by_last_task_update, -> {
    joins("LEFT JOIN tasks ON tasks.project_id = projects.id AND tasks.completed = false AND tasks.archived = false")
      .group("projects.id")
      .order(Arel.sql('COALESCE(MAX(tasks.updated_at), projects.updated_at) DESC'))
  }
  
  # Color-related methods
  def color_classes
    return '' unless color.present?
    
    case color
    when 'red'
      'border-l-4 border-l-red-500 bg-red-50'
    when 'orange'
      'border-l-4 border-l-orange-500 bg-orange-50'
    when 'yellow'
      'border-l-4 border-l-yellow-500 bg-yellow-50'
    when 'green'
      'border-l-4 border-l-green-500 bg-green-50'
    when 'blue'
      'border-l-4 border-l-blue-500 bg-blue-50'
    when 'purple'
      'border-l-4 border-l-purple-500 bg-purple-50'
    when 'pink'
      'border-l-4 border-l-pink-500 bg-pink-50'
    when 'gray'
      'border-l-4 border-l-gray-500 bg-gray-50'
    else
      ''
    end
  end

  SEGMENT_PRIORITIES = %w[high medium low leisure].freeze

  # The "weighted progress" score (see priority_weighted_completed_amount_sql)
  # is: completion_fraction * task_count^SIZE_EXPONENT * avg_priority_weight^PRIORITY_EXPONENT
  # - task count and priority mix are deliberately separate exponents so
  # each can be tuned independently instead of both riding on one combined
  # total_weight term:
  # - SIZE_EXPONENT dampens how much raw task count matters, so a finished
  #   small project isn't dominated by a barely-started huge one (1.0 would
  #   weight count linearly; 0.0 would ignore it).
  # - PRIORITY_EXPONENT amplifies how much the project's average task
  #   priority matters (1.0 = linear, e.g. an all-medium project scores 3x
  #   an otherwise-identical all-leisure one; >1.0 compounds faster).
  WEIGHTED_PROGRESS_SIZE_EXPONENT = 0.75
  WEIGHTED_PROGRESS_PRIORITY_EXPONENT = 1.5

  # Priority-weighted: a completed high-priority task counts more toward
  # progress than a completed leisure one (see Task::PRIORITY_WEIGHT_SQL).
  # Archived tasks are excluded, matching ReportStatsService.
  def completion_percentage
    scope = tasks.not_archived
    return 0 if scope.empty?

    total_weight = scope.sum(Arel.sql(Task::PRIORITY_WEIGHT_SQL))
    return 0 if total_weight.zero?

    completed_weight = scope.where(completed: true).sum(Arel.sql(Task::PRIORITY_WEIGHT_SQL))
    ((completed_weight.to_f / total_weight) * 100).round
  end

  # Correlated-subquery SQL (not GROUP BY) so it can be used to ORDER BY on
  # the (paginated) projects index without breaking Kaminari's count query.
  def self.priority_weighted_completion_ratio_sql
    weight = Task::PRIORITY_WEIGHT_SQL
    "COALESCE((SELECT SUM(CASE WHEN tasks.completed THEN #{weight} ELSE 0 END)::float / NULLIF(SUM(#{weight}), 0) " \
    "FROM tasks WHERE tasks.project_id = projects.id AND tasks.archived = false), 0)"
  end

  # completion_fraction * task_count^SIZE_EXPONENT * avg_priority_weight^PRIORITY_EXPONENT
  # - see WEIGHTED_PROGRESS_SIZE_EXPONENT / WEIGHTED_PROGRESS_PRIORITY_EXPONENT.
  # Used to sort "substantial, mostly-done, high-priority-heavy projects"
  # above trivially-small or low-priority ones, without letting raw size
  # alone dominate completion rate or priority mix.
  def self.priority_weighted_completed_amount_sql
    weight = Task::PRIORITY_WEIGHT_SQL
    size_exponent = WEIGHTED_PROGRESS_SIZE_EXPONENT
    priority_exponent = WEIGHTED_PROGRESS_PRIORITY_EXPONENT
    "COALESCE((SELECT " \
    "(SUM(CASE WHEN tasks.completed THEN #{weight} ELSE 0 END)::float / NULLIF(SUM(#{weight}), 0)) " \
    "* POWER(COUNT(*)::float, #{size_exponent}) " \
    "* POWER(SUM(#{weight})::float / NULLIF(COUNT(*), 0), #{priority_exponent}) " \
    "FROM tasks WHERE tasks.project_id = projects.id AND tasks.archived = false), 0)"
  end

  # Segments for the completed portion of the progress bar, one per priority
  # among the *completed* tasks (skipped when zero), each as a percent of
  # the project's total weight. These always sum to completion_percentage -
  # the remainder of the bar is left uncolored, matching the plain number
  # shown underneath - while making which priorities that progress came from
  # visible (e.g. a mostly-red fill means the completed work skewed
  # high-priority).
  def progress_bar_segments
    scope = tasks.not_archived
    total_weight = scope.sum(Arel.sql(Task::PRIORITY_WEIGHT_SQL)).to_f
    return [] if total_weight.zero?

    raw_completed_weights = scope.where(completed: true).group(:priority).sum(Arel.sql(Task::PRIORITY_WEIGHT_SQL))

    completed_weights = Hash.new(0)
    raw_completed_weights.each do |priority, weight|
      key = SEGMENT_PRIORITIES.include?(priority) ? priority : "low"
      completed_weights[key] += weight
    end

    SEGMENT_PRIORITIES.each_with_object([]) do |priority, segments|
      weight = completed_weights[priority]
      next if weight.zero?

      segments << { priority: priority, percent: (weight.to_f / total_weight * 100).round(1) }
    end
  end

  # Mirrors shared/_priority_badge's color mapping (high/medium/leisure get
  # their own hue, everything else - "low" included - falls back to green).
  def self.progress_segment_color_class(priority)
    case priority
    when "high" then "bg-red-500"
    when "medium" then "bg-yellow-500"
    when "leisure" then "bg-purple-500"
    else "bg-green-500"
    end
  end

  def status
    return 'not_started' if tasks.empty?
    return 'completed' if completion_percentage == 100
    not_started_name = Status.default_statuses[:not_started]
    return 'in_progress' if tasks.not_completed.joins(:status).where.not(statuses: { name: not_started_name }).exists?
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
  def create_default_statuses!(force: false)
    return if statuses.any? && !force  # Don't recreate if statuses already exist (unless forced)
    Status.default_statuses.each do |key, name|
      statuses.find_or_create_by!(name: name)
    end
  end

  # I18n display methods
  def default_priority_display
    I18n.t("priorities.#{default_priority}")
  end

  def color_display
    return 'None' unless color.present?
    color.titleize
  end

  private

  def warn_if_similar_title_exists
    return if duplicate_title_check_disabled
    return if ActiveModel::Type::Boolean.new.cast(confirm_duplicate)
    return if title.blank? || user.nil?
    # On update, only re-check when the title itself was actually edited -
    # otherwise saving any unrelated field on a record that happens to sit
    # near another title (e.g. one grandfathered in via confirm_duplicate,
    # or created before this check existed) would be blocked forever.
    # Always true for a new record, so create is unaffected.
    return unless title_changed?

    # .where forces a real query instead of Enumerable#detect reading the
    # association's in-memory target - important because user.projects.build
    # (what the controller actually uses) adds this very (unsaved, id-less)
    # record to that target, which would otherwise match itself every time.
    match = user.projects.where.not(id: id).detect { |other| StringSimilarity.similar?(title, other.title) }
    return unless match

    errors.add(:title, :similar_exists, message: "is very similar to an existing project: \"#{match.title}\"")
  end

  def reset_duplicate_confirmation
    self.confirm_duplicate = false
  end

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
