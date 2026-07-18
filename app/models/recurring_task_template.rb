class RecurringTaskTemplate < ApplicationRecord
  BASE_UNITS = %w[day week month year].freeze

  # interval is either a positive whole number (every N units) or exactly
  # 0.5, meaning twice per single unit: the second occurrence lands on the
  # midpoint date of that unit's period (half a month, half a year, ...)
  # rather than on a separately configured day. "day" + 0.5 is disallowed -
  # see #day_unit_disallows_half_interval - since a due_date only has
  # day-level precision, so a half-day period has no distinct calendar date
  # for the second occurrence to land on.
  HALF_INTERVAL = 0.5

  # Applied per-template: once a template has this many of its own generated
  # tasks sitting incomplete, generation stops (and the user is notified)
  # until the backlog is worked down below the cap again.
  MAX_PENDING_GENERATED_TASKS = 5

  belongs_to :project
  belongs_to :user
  belongs_to :task_category, optional: true
  has_many :tasks, dependent: :nullify

  validates :title, presence: true
  validates :base_unit, inclusion: { in: BASE_UNITS }
  validates :start_date, presence: true
  validates :priority, inclusion: { in: %w[low medium high leisure] }, allow_nil: true
  validates :interval, presence: true
  validate :interval_is_half_or_positive_whole_number
  validate :day_unit_disallows_half_interval

  scope :active, -> { where(active: true) }

  # Single entry point for all three generation triggers (opportunistic
  # before_action, the Solid Queue recurring job, and the app-startup check).
  # One rescue per template so a bad record can't block the rest.
  def self.generate_all_due!
    ensure_paper_trail_request_context!

    active.find_each do |template|
      template.generate_pending_tasks!
    rescue StandardError => e
      Rails.logger.error("RecurringTaskTemplate##{template.id} generation failed: #{e.message}")
    end
  end

  # Task/Project/Comment's PaperTrail metadata methods read
  # PaperTrail.request.controller_info[:ip]/[:user_agent] unconditionally -
  # only ApplicationController ever populates that, so task creation from a
  # job or the startup initializer (no HTTP request in progress) would
  # otherwise raise. Only fills it in when unset, so a real request's
  # controller_info (set by the opportunistic before_action's caller) is
  # never clobbered.
  def self.ensure_paper_trail_request_context!
    PaperTrail.request.whodunnit ||= "system:recurring_task_generation"
    PaperTrail.request.controller_info ||= { ip: nil, user_agent: "RecurringTaskTemplate.generate_all_due!" }
  end
  private_class_method :ensure_paper_trail_request_context!

  # Idempotent and safe to call repeatedly (e.g. on every page load): a no-op
  # unless a new period is actually due. Never generates more than one task
  # per call - if periods were missed while the app wasn't running, they are
  # skipped and only the most recent overdue period gets a task.
  def generate_pending_tasks!
    return unless active?

    candidate = upcoming_period_start
    target = period_start_for(Date.current)

    return if candidate > target
    return if target == last_generated_period_start

    if backlog_at_or_over_cap?
      pause_for_backlog!
      return
    end

    resume_from_backlog_pause! if paused?
    generate_task_for_period!(target)
  end

  # The period-start date generation is currently waiting to produce a task
  # for, i.e. the period right after the last one generated (or the
  # schedule's own first period, if nothing has been generated yet).
  def upcoming_period_start
    last_generated_period_start ? next_period_start_after(last_generated_period_start) : period_start_for(start_date)
  end

  def half_interval?
    interval.to_f == HALF_INTERVAL
  end

  def paused?
    paused_at.present?
  end

  def pending_generated_tasks_count
    tasks.not_archived.not_completed.count
  end

  def status_key
    return :inactive unless active?
    return :paused if paused?

    :active
  end

  def status_badge_classes
    case status_key
    when :active
      "bg-green-100 text-green-800"
    when :paused
      "bg-yellow-100 text-yellow-800"
    else
      "bg-gray-100 text-gray-800"
    end
  end

  # Human, translated description of the recurrence, e.g. "Every 3 months" or
  # "Twice a month".
  def frequency_display
    if half_interval?
      I18n.t("views.recurring_task_templates.index.frequencies.twice_per_#{base_unit}")
    else
      I18n.t("views.recurring_task_templates.index.frequencies.every_#{base_unit}", count: interval.to_i)
    end
  end

  # The period-start date (<= `date`) that contains `date`, anchored to
  # start_date.
  def period_start_for(date)
    date = date.to_date
    half_interval? ? half_period_start_for(date) : whole_period_start_for(date, interval.to_i)
  end

  def next_period_start_after(period_start)
    half_interval? ? half_next_period_start_after(period_start) : whole_next_period_start_after(period_start, interval.to_i)
  end

  # Human, date-based label baked into the generated task's title. This is
  # the "unique ID" for the period: kept in the title text itself (not just
  # the due_date field or the recurring_task_template_id FK) so a task's
  # identity/history survives even if the template is later deleted or the
  # due date is edited. Half-interval schedules always use the full date -
  # a coarser label (e.g. just "2026-07" for two half-month occurrences)
  # would collide between the two halves of the same period.
  def period_label_for(period_start)
    return period_start.strftime("%Y-%m-%d") if half_interval?

    case base_unit
    when "day"
      period_start.strftime("%Y-%m-%d")
    when "week"
      "Week of #{period_start.strftime('%Y-%m-%d')}"
    when "month"
      period_start.strftime("%Y-%m")
    when "year"
      period_start.strftime("%Y")
    end
  end

  private

  # --- whole-number interval (every N units) ---

  # "week" with interval N is exactly "day" with interval N*7 - both start_date's
  # weekday anchor and the interval are already fully captured by the day count.
  def effective_interval_days(n)
    base_unit == "week" ? n * 7 : n
  end

  def whole_period_start_for(date, n)
    case base_unit
    when "day", "week"
      day_count_period_start_for(date, n)
    when "month"
      month_period_start_for(date, n)
    when "year"
      year_period_start_for(date, n)
    end
  end

  def whole_next_period_start_after(period_start, n)
    case base_unit
    when "day", "week"
      period_start + effective_interval_days(n)
    when "month"
      month_batch_anchor(month_periods_elapsed(period_start, n) + 1, n)
    when "year"
      year_batch_anchor(year_periods_elapsed(period_start, n) + 1, n)
    end
  end

  def day_count_period_start_for(date, n)
    step = effective_interval_days(n)
    periods_elapsed = (date - start_date).to_i / step
    start_date + periods_elapsed * step
  end

  def month_periods_elapsed(date, n)
    total_months = (date.year - start_date.year) * 12 + (date.month - start_date.month)
    total_months / n
  end

  def month_batch_anchor(periods_elapsed, n)
    total = (start_date.month - 1) + periods_elapsed * n
    year = start_date.year + total / 12
    month = total % 12 + 1
    monthly_anchor_date(year, month)
  end

  def month_period_start_for(date, n)
    periods_elapsed = month_periods_elapsed(date, n)
    candidate = month_batch_anchor(periods_elapsed, n)
    return candidate if candidate <= date

    month_batch_anchor(periods_elapsed - 1, n)
  end

  def year_periods_elapsed(date, n)
    (date.year - start_date.year) / n
  end

  def year_batch_anchor(periods_elapsed, n)
    yearly_anchor_date(start_date.year + periods_elapsed * n)
  end

  def year_period_start_for(date, n)
    periods_elapsed = year_periods_elapsed(date, n)
    candidate = year_batch_anchor(periods_elapsed, n)
    return candidate if candidate <= date

    year_batch_anchor(periods_elapsed - 1, n)
  end

  def monthly_anchor_date(year, month)
    day = [start_date.day, Date.new(year, month, -1).day].min
    Date.new(year, month, day)
  end

  def yearly_anchor_date(year)
    month = start_date.month
    day = [start_date.day, Date.new(year, month, -1).day].min
    Date.new(year, month, day)
  end

  # --- half interval (twice per single unit, via the period's midpoint) ---

  def half_period_start_for(date)
    containing_start = whole_period_start_for(date, 1)
    midpoint = period_midpoint(containing_start)
    date >= midpoint ? midpoint : containing_start
  end

  def half_next_period_start_after(period_start)
    containing_start = whole_period_start_for(period_start, 1)
    midpoint = period_midpoint(containing_start)

    period_start < midpoint ? midpoint : whole_next_period_start_after(containing_start, 1)
  end

  # The midpoint of the single-unit period starting at `containing_start`:
  # the period's length (in days) divided by two, rounded down, added back
  # to the start - e.g. a 30-day month lands on day 15, a 365-day year on
  # day 182.
  def period_midpoint(containing_start)
    containing_end = whole_next_period_start_after(containing_start, 1)
    containing_start + (containing_end - containing_start).to_i / 2
  end

  # --- shared ---

  def interval_is_half_or_positive_whole_number
    return if interval.blank?
    return if interval.to_f == HALF_INTERVAL
    return if interval == interval.to_i && interval >= 1

    errors.add(:interval, "must be a positive whole number, or 0.5 for twice per period")
  end

  def day_unit_disallows_half_interval
    return unless base_unit == "day" && interval.present? && interval.to_f == HALF_INTERVAL

    errors.add(:interval, "twice-daily schedules aren't supported (tasks only track a due date, not a time)")
  end

  def backlog_at_or_over_cap?
    pending_generated_tasks_count >= MAX_PENDING_GENERATED_TASKS
  end

  def pause_for_backlog!
    return if paused?

    update!(paused_at: Time.current)
    Notification.notify!(
      user: user,
      title: "Recurring schedule paused: #{title}",
      body: "\"#{title}\" has #{MAX_PENDING_GENERATED_TASKS} or more unfinished generated tasks, so no new tasks will be created until some are completed or archived.",
      kind: "recurring_schedule_paused",
      link_path: Rails.application.routes.url_helpers.recurring_task_templates_path
    )
  end

  def resume_from_backlog_pause!
    update!(paused_at: nil)
  end

  def generate_task_for_period!(period_start)
    project.create_task!(
      title: "#{title} (#{period_label_for(period_start)})",
      description: description,
      priority: priority,
      user: user,
      task_category: task_category,
      due_date: period_start,
      recurring_task_template: self
    )
    update!(last_generated_period_start: period_start)
  end
end
