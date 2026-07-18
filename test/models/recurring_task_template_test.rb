require "test_helper"

class RecurringTaskTemplateTest < ActiveSupport::TestCase
  def setup
    @user = users(:one)
    @project = projects(:one)
    setup_paper_trail
  end

  def teardown
    teardown_paper_trail
  end

  def build_template(attrs = {})
    RecurringTaskTemplate.new({
      title: "Water the plants",
      project: @project,
      user: @user,
      base_unit: "month",
      interval: 1,
      start_date: 6.months.ago.to_date
    }.merge(attrs))
  end

  # ============================================================
  # Validations
  # ============================================================

  test "requires a title" do
    template = build_template(title: nil)
    assert_not template.valid?
    assert_includes template.errors[:title], "can't be blank"
  end

  test "requires a valid base_unit" do
    template = build_template(base_unit: "fortnight")
    assert_not template.valid?
    assert_includes template.errors[:base_unit], "is not included in the list"
  end

  test "requires a start date" do
    template = build_template(start_date: nil)
    assert_not template.valid?
    assert_includes template.errors[:start_date], "can't be blank"
  end

  test "requires an interval" do
    template = build_template(interval: nil)
    assert_not template.valid?
    assert_includes template.errors[:interval], "can't be blank"
  end

  test "interval must be a positive whole number or exactly 0.5" do
    [0, -1, -0.5].each do |bad|
      template = build_template(interval: bad)
      assert_not template.valid?, "#{bad.inspect} should be invalid"
      assert_includes template.errors[:interval], "must be a positive whole number, or 0.5 for twice per period"
    end

    # Fractions other than 0.5 (e.g. 1.5, 2.5, 0.25) are not supported.
    template = build_template(base_unit: "week", interval: 1.5)
    assert_not template.valid?
    assert_includes template.errors[:interval], "must be a positive whole number, or 0.5 for twice per period"

    [1, 2, 3, 6, 12].each do |good|
      template = build_template(interval: good)
      assert template.valid?, "#{good.inspect} should be valid: #{template.errors.full_messages}"
    end

    template = build_template(base_unit: "week", interval: 0.5)
    assert template.valid?
  end

  test "half interval (0.5) is disallowed for the day unit" do
    template = build_template(base_unit: "day", interval: 0.5)
    assert_not template.valid?
    assert_includes template.errors[:interval], "twice-daily schedules aren't supported (tasks only track a due date, not a time)"
  end

  test "half interval (0.5) is allowed for week, month, and year" do
    %w[week month year].each do |unit|
      template = build_template(base_unit: unit, interval: 0.5)
      assert template.valid?, "#{unit} + 0.5 should be valid: #{template.errors.full_messages}"
    end
  end

  # ============================================================
  # period_start_for / next_period_start_after - whole intervals
  # ============================================================

  test "day unit, interval 1 (daily): period start is the date itself" do
    template = build_template(base_unit: "day", interval: 1, start_date: Date.new(2026, 1, 1))
    assert_equal Date.new(2026, 7, 15), template.period_start_for(Date.new(2026, 7, 15))
    assert_equal Date.new(2026, 7, 16), template.next_period_start_after(Date.new(2026, 7, 15))
  end

  test "day unit, interval 3 (every 3 days): batches from the start date" do
    template = build_template(base_unit: "day", interval: 3, start_date: Date.new(2026, 7, 1))

    assert_equal Date.new(2026, 7, 1), template.period_start_for(Date.new(2026, 7, 1))
    assert_equal Date.new(2026, 7, 1), template.period_start_for(Date.new(2026, 7, 2))
    assert_equal Date.new(2026, 7, 1), template.period_start_for(Date.new(2026, 7, 3))
    assert_equal Date.new(2026, 7, 4), template.period_start_for(Date.new(2026, 7, 4))
    assert_equal Date.new(2026, 7, 4), template.period_start_for(Date.new(2026, 7, 6))
    assert_equal Date.new(2026, 7, 4), template.next_period_start_after(Date.new(2026, 7, 1))
  end

  test "week unit, interval 1 (weekly): anchors to the start date's weekday" do
    start_date = Date.new(2026, 7, 6) # a Monday
    template = build_template(base_unit: "week", interval: 1, start_date: start_date)

    assert_equal Date.new(2026, 7, 6), template.period_start_for(Date.new(2026, 7, 6))
    assert_equal Date.new(2026, 7, 6), template.period_start_for(Date.new(2026, 7, 10))
    assert_equal Date.new(2026, 7, 13), template.period_start_for(Date.new(2026, 7, 13))
    assert_equal Date.new(2026, 7, 13), template.next_period_start_after(Date.new(2026, 7, 6))
  end

  test "week unit, interval 2 (biweekly): skips every other week boundary" do
    start_date = Date.new(2026, 7, 6) # a Monday
    template = build_template(base_unit: "week", interval: 2, start_date: start_date)

    assert_equal Date.new(2026, 7, 6), template.period_start_for(Date.new(2026, 7, 12))
    assert_equal Date.new(2026, 7, 20), template.period_start_for(Date.new(2026, 7, 20))
    assert_equal Date.new(2026, 7, 20), template.period_start_for(Date.new(2026, 7, 26))
    assert_equal Date.new(2026, 7, 20), template.next_period_start_after(Date.new(2026, 7, 6))
  end

  test "month unit, interval 1 (monthly): clamps a 31st anchor into shorter months" do
    template = build_template(base_unit: "month", interval: 1, start_date: Date.new(2026, 1, 31))

    assert_equal Date.new(2026, 1, 31), template.period_start_for(Date.new(2026, 1, 31))
    assert_equal Date.new(2026, 1, 31), template.period_start_for(Date.new(2026, 2, 15))
    assert_equal Date.new(2026, 2, 28), template.period_start_for(Date.new(2026, 2, 28))
    assert_equal Date.new(2026, 2, 28), template.next_period_start_after(Date.new(2026, 1, 31))
    assert_equal Date.new(2026, 3, 31), template.next_period_start_after(Date.new(2026, 2, 28))
  end

  test "month unit, interval 3 (quarterly): skips the two in-between months" do
    template = build_template(base_unit: "month", interval: 3, start_date: Date.new(2026, 1, 15))

    assert_equal Date.new(2026, 1, 15), template.period_start_for(Date.new(2026, 3, 1))
    assert_equal Date.new(2026, 4, 15), template.period_start_for(Date.new(2026, 4, 20))
    assert_equal Date.new(2026, 4, 15), template.period_start_for(Date.new(2026, 6, 1))
    assert_equal Date.new(2026, 7, 15), template.period_start_for(Date.new(2026, 7, 15))
    assert_equal Date.new(2026, 4, 15), template.next_period_start_after(Date.new(2026, 1, 15))
  end

  test "month unit, interval 6 (semiannual)" do
    template = build_template(base_unit: "month", interval: 6, start_date: Date.new(2026, 1, 15))

    assert_equal Date.new(2026, 1, 15), template.period_start_for(Date.new(2026, 6, 1))
    assert_equal Date.new(2026, 7, 15), template.period_start_for(Date.new(2026, 7, 15))
    assert_equal Date.new(2026, 7, 15), template.next_period_start_after(Date.new(2026, 1, 15))
  end

  test "year unit, interval 1 (yearly): clamps a leap-day anchor in non-leap years" do
    template = build_template(base_unit: "year", interval: 1, start_date: Date.new(2024, 2, 29))

    assert_equal Date.new(2024, 2, 29), template.period_start_for(Date.new(2024, 2, 29))
    assert_equal Date.new(2025, 2, 28), template.period_start_for(Date.new(2025, 3, 1))
    assert_equal Date.new(2025, 2, 28), template.next_period_start_after(Date.new(2024, 2, 29))
  end

  test "year unit, interval 2 (biennial): skips the in-between year" do
    template = build_template(base_unit: "year", interval: 2, start_date: Date.new(2026, 1, 15))

    assert_equal Date.new(2026, 1, 15), template.period_start_for(Date.new(2027, 1, 15))
    assert_equal Date.new(2028, 1, 15), template.period_start_for(Date.new(2028, 1, 15))
    assert_equal Date.new(2028, 1, 15), template.next_period_start_after(Date.new(2026, 1, 15))
  end

  # ============================================================
  # period_start_for / next_period_start_after - half interval (0.5):
  # the second occurrence lands on the midpoint of the base period
  # (period length in days, floor-divided by two).
  # ============================================================

  test "week unit, interval 0.5 (twice weekly): midpoint is 3 days after the weekly anchor" do
    start_date = Date.new(2026, 7, 6) # a Monday
    template = build_template(base_unit: "week", interval: 0.5, start_date: start_date)

    # Period: Mon Jul 6 - Sun Jul 12 (7 days). Midpoint = Jul 6 + 3 = Thu Jul 9.
    assert_equal Date.new(2026, 7, 6), template.period_start_for(Date.new(2026, 7, 6))
    assert_equal Date.new(2026, 7, 6), template.period_start_for(Date.new(2026, 7, 8))
    assert_equal Date.new(2026, 7, 9), template.period_start_for(Date.new(2026, 7, 9))
    assert_equal Date.new(2026, 7, 9), template.period_start_for(Date.new(2026, 7, 12))
    assert_equal Date.new(2026, 7, 13), template.period_start_for(Date.new(2026, 7, 13))

    assert_equal Date.new(2026, 7, 9), template.next_period_start_after(Date.new(2026, 7, 6))
    assert_equal Date.new(2026, 7, 13), template.next_period_start_after(Date.new(2026, 7, 9))
  end

  test "month unit, interval 0.5 (twice monthly): midpoint accounts for the month's actual length" do
    template = build_template(base_unit: "month", interval: 0.5, start_date: Date.new(2026, 1, 1))

    # January: 31 days, Jan 1 - Feb 1. Midpoint = Jan 1 + 15 = Jan 16.
    assert_equal Date.new(2026, 1, 1), template.period_start_for(Date.new(2026, 1, 1))
    assert_equal Date.new(2026, 1, 1), template.period_start_for(Date.new(2026, 1, 15))
    assert_equal Date.new(2026, 1, 16), template.period_start_for(Date.new(2026, 1, 16))
    assert_equal Date.new(2026, 1, 16), template.period_start_for(Date.new(2026, 1, 31))
    assert_equal Date.new(2026, 1, 16), template.next_period_start_after(Date.new(2026, 1, 1))
    assert_equal Date.new(2026, 2, 1), template.next_period_start_after(Date.new(2026, 1, 16))

    # April: 30 days, Apr 1 - May 1. Midpoint = Apr 1 + 15 = Apr 16.
    assert_equal Date.new(2026, 4, 16), template.period_start_for(Date.new(2026, 4, 20))

    # February 2026 (non-leap): 28 days, Feb 1 - Mar 1. Midpoint = Feb 1 + 14 = Feb 15.
    assert_equal Date.new(2026, 2, 15), template.period_start_for(Date.new(2026, 2, 20))

    # February 2028 (leap): 29 days, Feb 1 - Mar 1. Midpoint = Feb 1 + 14 = Feb 15.
    assert_equal Date.new(2028, 2, 15), template.period_start_for(Date.new(2028, 2, 20))
  end

  test "month unit, interval 0.5, anchored mid-month" do
    template = build_template(base_unit: "month", interval: 0.5, start_date: Date.new(2026, 1, 10))

    # January: Jan 10 - Feb 10 (31 days). Midpoint = Jan 10 + 15 = Jan 25.
    assert_equal Date.new(2026, 1, 10), template.period_start_for(Date.new(2026, 1, 24))
    assert_equal Date.new(2026, 1, 25), template.period_start_for(Date.new(2026, 1, 25))

    # February 2026: Feb 10 - Mar 10 (28 days). Midpoint = Feb 10 + 14 = Feb 24.
    assert_equal Date.new(2026, 2, 24), template.period_start_for(Date.new(2026, 2, 24))
  end

  test "year unit, interval 0.5 (twice yearly): midpoint accounts for leap years" do
    non_leap = build_template(base_unit: "year", interval: 0.5, start_date: Date.new(2026, 1, 1))
    # 2026: 365 days, Jan 1 2026 - Jan 1 2027. Midpoint = Jan 1 + 182 = Jul 2, 2026.
    assert_equal Date.new(2026, 1, 1), non_leap.period_start_for(Date.new(2026, 1, 1))
    assert_equal Date.new(2026, 1, 1), non_leap.period_start_for(Date.new(2026, 7, 1))
    assert_equal Date.new(2026, 7, 2), non_leap.period_start_for(Date.new(2026, 7, 2))
    assert_equal Date.new(2026, 7, 2), non_leap.period_start_for(Date.new(2026, 12, 31))
    assert_equal Date.new(2026, 7, 2), non_leap.next_period_start_after(Date.new(2026, 1, 1))
    assert_equal Date.new(2027, 1, 1), non_leap.next_period_start_after(Date.new(2026, 7, 2))

    leap = build_template(base_unit: "year", interval: 0.5, start_date: Date.new(2024, 1, 1))
    # 2024: 366 days, Jan 1 2024 - Jan 1 2025. Midpoint = Jan 1 + 183 = Jul 2, 2024.
    assert_equal Date.new(2024, 7, 2), leap.period_start_for(Date.new(2024, 7, 2))
    assert_equal Date.new(2024, 7, 2), leap.next_period_start_after(Date.new(2024, 1, 1))
  end

  # ============================================================
  # period_label_for
  # ============================================================

  test "period_label_for uses a coarser label for whole intervals but always a full date for half intervals" do
    daily = build_template(base_unit: "day", interval: 1)
    assert_equal "2026-07-15", daily.period_label_for(Date.new(2026, 7, 15))

    weekly = build_template(base_unit: "week", interval: 1)
    assert_equal "Week of 2026-07-13", weekly.period_label_for(Date.new(2026, 7, 13))

    monthly = build_template(base_unit: "month", interval: 3)
    assert_equal "2026-07", monthly.period_label_for(Date.new(2026, 7, 15))

    yearly = build_template(base_unit: "year", interval: 2)
    assert_equal "2026", yearly.period_label_for(Date.new(2026, 7, 15))

    # Half-interval labels must be unique between the two halves of the same
    # period, so they always carry the full date rather than "2026-07" twice.
    twice_monthly = build_template(base_unit: "month", interval: 0.5)
    assert_equal "2026-07-01", twice_monthly.period_label_for(Date.new(2026, 7, 1))
    assert_equal "2026-07-16", twice_monthly.period_label_for(Date.new(2026, 7, 16))
    assert_not_equal twice_monthly.period_label_for(Date.new(2026, 7, 1)), twice_monthly.period_label_for(Date.new(2026, 7, 16))
  end

  # ============================================================
  # frequency_display
  # ============================================================

  test "frequency_display describes the unit and interval" do
    assert_equal "Every day", build_template(base_unit: "day", interval: 1).frequency_display
    assert_equal "Every 3 days", build_template(base_unit: "day", interval: 3).frequency_display
    assert_equal "Every week", build_template(base_unit: "week", interval: 1).frequency_display
    assert_equal "Every 2 weeks", build_template(base_unit: "week", interval: 2).frequency_display
    assert_equal "Every month", build_template(base_unit: "month", interval: 1).frequency_display
    assert_equal "Every 3 months", build_template(base_unit: "month", interval: 3).frequency_display
    assert_equal "Every year", build_template(base_unit: "year", interval: 1).frequency_display
    assert_equal "Every 2 years", build_template(base_unit: "year", interval: 2).frequency_display

    assert_equal "Twice a week", build_template(base_unit: "week", interval: 0.5).frequency_display
    assert_equal "Twice a month", build_template(base_unit: "month", interval: 0.5).frequency_display
    assert_equal "Twice a year", build_template(base_unit: "year", interval: 0.5).frequency_display
  end

  # ============================================================
  # generate_pending_tasks! / generate_all_due!
  # ============================================================

  test "generate_pending_tasks! creates one task for a past-due schedule with a date-based title" do
    template = build_template(base_unit: "month", interval: 1, start_date: 6.months.ago.to_date)

    assert_difference("Task.count", 1) do
      template.generate_pending_tasks!
    end

    task = Task.order(created_at: :desc).first
    target = template.period_start_for(Date.current)
    assert_equal "Water the plants (#{template.period_label_for(target)})", task.title
    assert_equal template, task.recurring_task_template
    assert_equal target, task.due_date.to_date
    assert_equal target, template.reload.last_generated_period_start
  end

  test "generate_pending_tasks! only generates the most recent overdue period, skipping missed ones" do
    template = build_template(base_unit: "month", interval: 1, start_date: 6.months.ago.to_date)

    assert_difference("Task.count", 1) do
      template.generate_pending_tasks!
    end

    assert_no_difference("Task.count") do
      template.generate_pending_tasks!
    end
  end

  test "generate_pending_tasks! for a half-interval schedule produces both halves across successive calls, never both at once" do
    # Anchored so the first half of the current month is already due, but
    # not the second - simulated by pointing start_date far enough in the
    # past and walking last_generated_period_start forward by hand.
    template = build_template(base_unit: "month", interval: 0.5, start_date: 6.months.ago.to_date)
    template.save!

    first_target = template.period_start_for(Date.current)
    assert_difference("Task.count", 1) do
      template.generate_pending_tasks!
    end
    assert_equal first_target, template.reload.last_generated_period_start

    second_target = template.next_period_start_after(first_target)
    if second_target <= Date.current
      assert_difference("Task.count", 1) do
        template.generate_pending_tasks!
      end
      assert_equal second_target, template.reload.last_generated_period_start
      assert_not_equal first_target, second_target
    else
      assert_no_difference("Task.count") do
        template.generate_pending_tasks!
      end
    end
  end

  test "generate_pending_tasks! does nothing before the schedule's start date" do
    template = build_template(base_unit: "month", interval: 1, start_date: 1.month.from_now.to_date)

    assert_no_difference("Task.count") do
      template.generate_pending_tasks!
    end
    assert_nil template.last_generated_period_start
  end

  test "generate_pending_tasks! does nothing for an inactive schedule" do
    template = build_template(base_unit: "month", interval: 1, start_date: 6.months.ago.to_date, active: false)

    assert_no_difference("Task.count") do
      template.generate_pending_tasks!
    end
  end

  test "generate_pending_tasks! pauses and notifies once the backlog cap is hit, without generating or advancing" do
    template = build_template(base_unit: "month", interval: 1, start_date: 6.months.ago.to_date)
    template.save!

    RecurringTaskTemplate::MAX_PENDING_GENERATED_TASKS.times do |i|
      @project.create_task!(title: "Backlog #{i}", user: @user, recurring_task_template: template)
    end

    assert_no_difference("Task.count") do
      assert_difference("Notification.count", 1) do
        template.generate_pending_tasks!
      end
    end

    assert template.reload.paused?
    assert_nil template.last_generated_period_start

    notification = Notification.last
    assert_equal @user, notification.user
    assert_equal "recurring_schedule_paused", notification.kind

    # Calling again while still paused must not send a second notification.
    assert_no_difference("Notification.count") do
      template.generate_pending_tasks!
    end
  end

  test "generate_pending_tasks! auto-resumes and generates once the backlog clears" do
    template = build_template(base_unit: "month", interval: 1, start_date: 6.months.ago.to_date)
    template.save!

    tasks = RecurringTaskTemplate::MAX_PENDING_GENERATED_TASKS.times.map do |i|
      @project.create_task!(title: "Backlog #{i}", user: @user, recurring_task_template: template)
    end
    template.generate_pending_tasks!
    assert template.reload.paused?

    Task.where(id: tasks.map(&:id)).update_all(completed: true)

    assert_difference("Task.count", 1) do
      template.generate_pending_tasks!
    end
    assert_not template.reload.paused?
  end

  test "generate_all_due! generates for every active schedule and skips inactive ones" do
    due = build_template(base_unit: "month", interval: 1, start_date: 6.months.ago.to_date)
    due.save!
    not_due = build_template(title: "Not due yet", base_unit: "month", interval: 1, start_date: 1.month.from_now.to_date)
    not_due.save!
    inactive = build_template(title: "Inactive", base_unit: "month", interval: 1, start_date: 6.months.ago.to_date, active: false)
    inactive.save!

    assert_difference("Task.count", 1) do
      RecurringTaskTemplate.generate_all_due!
    end

    assert_not_nil due.reload.last_generated_period_start
    assert_nil not_due.reload.last_generated_period_start
    assert_nil inactive.reload.last_generated_period_start
  end

  test "deleting a schedule nullifies its generated tasks instead of destroying them" do
    template = build_template(base_unit: "month", interval: 1, start_date: 6.months.ago.to_date)
    template.save!
    template.generate_pending_tasks!
    task = Task.order(created_at: :desc).first

    assert_no_difference("Task.count") do
      template.destroy
    end
    assert_nil task.reload.recurring_task_template_id
  end
end
