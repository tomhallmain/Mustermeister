require "test_helper"

class TaskToolsServiceTest < ActiveSupport::TestCase
  def setup
    @user = users(:one)
    setup_paper_trail(@user)
  end

  def teardown
    teardown_paper_trail
  end

  test "TOOL_NAMES lists all eight tools" do
    assert_equal(
      %w[project_summary status_breakdown overdue_tasks high_priority_open_tasks
         open_tasks_by_priorities recent_tasks search_tasks workload],
      TaskToolsService::TOOL_NAMES
    )
  end

  test "run returns an error for an unknown tool name" do
    service = TaskToolsService.new(user: @user)
    result = service.run("not_a_real_tool", {})
    assert_equal "Unknown tool: not_a_real_tool", result[:error]
  end

  test "formatted tasks include description and completed" do
    task = tasks(:one)
    task.update!(description: "Some details", completed: true)

    service = TaskToolsService.new(user: @user)
    payload = service.run("recent_tasks", { "days" => 3650, "limit" => 200 })
    formatted = payload[:items].find { |t| t[:id] == task.id }

    assert_equal "Some details", formatted[:description]
    assert_equal true, formatted[:completed]
  end

  test "long descriptions are truncated" do
    task = tasks(:one)
    task.update!(description: "x" * 2000)

    service = TaskToolsService.new(user: @user)
    payload = service.run("recent_tasks", { "days" => 3650, "limit" => 200 })
    formatted = payload[:items].find { |t| t[:id] == task.id }

    assert_equal TaskToolsService::DESCRIPTION_TRUNCATE_LENGTH, formatted[:description].length
    assert formatted[:description].end_with?("...")
  end

  test "open_tasks_by_priorities returns grouped compact payload" do
    service = TaskToolsService.new(user: @user)
    payload = service.run("open_tasks_by_priorities", { "priorities" => %w[medium high], "limit" => 50 })

    assert payload[:priorities].is_a?(Hash)
    assert payload[:returned_count].is_a?(Integer)
    assert payload[:total_matching_count].is_a?(Integer)
    assert payload[:limit].is_a?(Integer)

    any_task = payload[:priorities].values
      .flat_map { |p| p[:statuses].values }
      .flat_map { |s| s[:projects].values }
      .flatten
      .first

    if any_task
      assert any_task.key?(:updated_date)
      assert_not any_task.key?(:updated_at)
      assert_match(/\A\d{4}-\d{2}-\d{2}\z/, any_task[:updated_date])
    end
  end

  test "excluded projects are not visible to tools" do
    excluded_project = projects(:reprioritize_test)
    included_fixture_title = tasks(:two).title
    excluded_fixture_title = tasks(:reprioritize_high).title

    service = TaskToolsService.new(user: @user, excluded_project_ids: [excluded_project.id])
    payload = service.run("open_tasks_by_priorities", { "priorities" => %w[high], "limit" => 200 })

    titles = payload[:priorities].values
      .flat_map { |priority| priority[:statuses].values }
      .flat_map { |status_group| status_group[:projects].values }
      .flatten
      .map { |task| task[:title] }

    assert_includes titles, included_fixture_title
    assert_not_includes titles, excluded_fixture_title
  end

  test "a model-supplied project_ids argument targeting an excluded project is still filtered out" do
    excluded_project = Project.create!(title: "Confidential Project", user: @user)
    excluded_project.create_task!(title: "Top Secret Task", user: @user)

    service = TaskToolsService.new(user: @user, excluded_project_ids: [excluded_project.id])
    # The caller explicitly asks for the excluded project by id - simulating
    # an attempt to route around exclusion via tool arguments rather than it
    # simply never being mentioned.
    payload = service.run("recent_tasks", { "project_ids" => [excluded_project.id], "days" => 3650, "limit" => 200 })

    assert_equal 0, payload[:returned_count]
    assert_equal [], payload[:items]
  end

  test "project_summary omits excluded projects entirely" do
    excluded_project = Project.create!(title: "Confidential Project", user: @user)
    excluded_project.create_task!(title: "Top Secret Task", user: @user)

    service = TaskToolsService.new(user: @user, excluded_project_ids: [excluded_project.id])
    rows = service.run("project_summary", {})

    assert_not_includes rows.map { |r| r[:project] }, "Confidential Project"
  end

  test "overdue_tasks excludes tasks from excluded projects" do
    excluded_project = Project.create!(title: "Confidential Project", user: @user)
    excluded_project.create_task!(title: "Overdue Secret Task", user: @user, completed: false, due_date: 3.days.ago)

    service = TaskToolsService.new(user: @user, excluded_project_ids: [excluded_project.id])
    payload = service.run("overdue_tasks", { "limit" => 200 })

    assert_not_includes payload[:items].map { |t| t[:title] }, "Overdue Secret Task"
  end

  test "high_priority_open_tasks excludes tasks from excluded projects" do
    excluded_project = Project.create!(title: "Confidential Project", user: @user)
    excluded_project.create_task!(title: "High Priority Secret Task", user: @user, completed: false, priority: "high")

    service = TaskToolsService.new(user: @user, excluded_project_ids: [excluded_project.id])
    payload = service.run("high_priority_open_tasks", { "limit" => 200 })

    assert_not_includes payload[:items].map { |t| t[:title] }, "High Priority Secret Task"
  end

  test "search_tasks excludes matches from excluded projects" do
    excluded_project = Project.create!(title: "Confidential Project", user: @user)
    excluded_project.create_task!(title: "Zephyr Secret Task", user: @user)
    included_project = projects(:one)
    included_project.create_task!(title: "Zephyr Visible Task", user: @user)

    service = TaskToolsService.new(user: @user, excluded_project_ids: [excluded_project.id])
    payload = service.run("search_tasks", { "keyword" => "zephyr", "limit" => 200 })

    titles = payload[:items].map { |t| t[:title] }
    assert_includes titles, "Zephyr Visible Task"
    assert_not_includes titles, "Zephyr Secret Task"
  end

  test "status_breakdown counts exclude tasks from excluded projects" do
    excluded_project = Project.create!(title: "Confidential Project", user: @user)
    excluded_project.create_task!(title: "Secret Task", user: @user)

    with_exclusion = TaskToolsService.new(user: @user, excluded_project_ids: [excluded_project.id]).run("status_breakdown", {})
    without_exclusion = TaskToolsService.new(user: @user).run("status_breakdown", {})

    assert_operator with_exclusion.values.sum, :<, without_exclusion.values.sum
  end

  test "formatted tasks expose estimated_minutes only when set" do
    tasks(:one).update!(estimated_minutes: 45)
    tasks(:two).update!(estimated_minutes: nil)

    service = TaskToolsService.new(user: @user)
    payload = service.run("recent_tasks", { "days" => 3650, "limit" => 200 })

    with_estimate = payload[:items].find { |t| t[:id] == tasks(:one).id }
    without_estimate = payload[:items].find { |t| t[:id] == tasks(:two).id }

    assert_equal 45, with_estimate[:estimated_minutes]
    assert_not without_estimate.key?(:estimated_minutes)
  end

  test "workload aggregates open tasks per day with priority weighting and estimated minutes" do
    project = Project.create!(title: "Workload Project", user: @user)
    due = Date.new(2027, 3, 1).beginning_of_day
    project.create_task!(title: "Refactor billing exporter", user: @user, priority: "high", due_date: due, estimated_minutes: 60)
    project.create_task!(title: "Zebra migration notes", user: @user, priority: "low", due_date: due, estimated_minutes: 30)
    project.create_task!(title: "Quarterly archive sweep", user: @user, priority: "high", due_date: due, completed: true)

    payload = TaskToolsService.new(user: @user).run(
      "workload",
      { "from" => "2027-03-01", "to" => "2027-03-03", "project_ids" => [project.id] }
    )

    assert_equal({ from: "2027-03-01", to: "2027-03-03" }, payload[:range])
    assert_equal %w[2027-03-01 2027-03-02 2027-03-03], payload[:days].map { |d| d[:date] }

    busy_day = payload[:days].first
    assert_equal 2, busy_day[:task_count]
    assert_equal 6.0, busy_day[:weighted_load]
    assert_equal 90, busy_day[:estimated_minutes]

    empty_day = payload[:days].last
    assert_equal 0, empty_day[:task_count]
    assert_equal 0.0, empty_day[:weighted_load]
    assert_equal 0, empty_day[:estimated_minutes]
  end

  test "workload excludes tasks from excluded projects" do
    excluded_project = Project.create!(title: "Confidential Project", user: @user)
    due = Date.new(2027, 4, 1).beginning_of_day
    excluded_project.create_task!(title: "Secret capacity work", user: @user, priority: "high", due_date: due)

    payload = TaskToolsService.new(user: @user, excluded_project_ids: [excluded_project.id])
      .run("workload", { "from" => "2027-04-01", "to" => "2027-04-01" })

    assert_equal 0, payload[:days].first[:task_count]
  end

  test "workload rejects a missing, unparseable, inverted or oversized range" do
    service = TaskToolsService.new(user: @user)

    assert_match(/required ISO dates/, service.run("workload", {})[:error])
    assert_match(/required ISO dates/, service.run("workload", { "from" => "not-a-date", "to" => "2027-03-01" })[:error])
    assert_match(/on or before/, service.run("workload", { "from" => "2027-03-05", "to" => "2027-03-01" })[:error])
    assert_match(/at most/, service.run("workload", { "from" => "2027-01-01", "to" => "2029-01-01" })[:error])
    assert_equal [], service.run("workload", {})[:days]
  end
end
