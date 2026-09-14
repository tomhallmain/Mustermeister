require "test_helper"

class TaskWriteToolsServiceTest < ActiveSupport::TestCase
  def setup
    @user = users(:one)
    setup_paper_trail(@user)
  end

  def teardown
    teardown_paper_trail
  end

  test "TOOL_NAMES lists only the two write-back tools" do
    assert_equal %w[set_scheduled_at set_status], TaskWriteToolsService::TOOL_NAMES
  end

  test "run returns an error for an unknown tool name" do
    assert_equal "Unknown tool: drop_tasks", service.run("drop_tasks", {})[:error]
  end

  test "set_scheduled_at stores and clears the slot without touching the due date" do
    task = tasks(:one)
    original_due_date = task.due_date

    result = service.run("set_scheduled_at", { "task_id" => task.id, "scheduled_at" => "2027-03-01T09:00:00Z" })

    assert_nil result[:error]
    assert_equal Time.utc(2027, 3, 1, 9), task.reload.scheduled_at
    assert_equal original_due_date, task.due_date

    service.run("set_scheduled_at", { "task_id" => task.id, "scheduled_at" => "" })
    assert_nil task.reload.scheduled_at
  end

  test "set_scheduled_at rejects an unparseable timestamp" do
    task = tasks(:one)

    result = service.run("set_scheduled_at", { "task_id" => task.id, "scheduled_at" => "next tuesday-ish" })

    assert_match(/ISO8601/, result[:error])
    assert_nil task.reload.scheduled_at
  end

  test "set_scheduled_at rejects a time of day with no date" do
    task = tasks(:one)

    result = service.run("set_scheduled_at", { "task_id" => task.id, "scheduled_at" => "09:00:00" })

    assert_match(/ISO8601/, result[:error])
    assert_nil task.reload.scheduled_at
  end

  test "set_scheduled_at requires the argument to be present at all" do
    assert_match(/required/, service.run("set_scheduled_at", { "task_id" => tasks(:one).id })[:error])
  end

  test "set_status moves a task by status name within its project" do
    task = tasks(:one)

    result = service.run("set_status", { "task_id" => task.id, "status_name" => "In Progress" })

    assert_nil result[:error]
    assert_equal "In Progress", task.reload.status.name
  end

  test "set_status rejects a status name that does not exist in the task's project" do
    task = tasks(:one)
    original_status_id = task.status_id

    result = service.run("set_status", { "task_id" => task.id, "status_name" => "Blocked" })

    assert_match(/No status named/, result[:error])
    assert_equal original_status_id, task.reload.status_id
  end

  test "set_status cannot borrow a status from another project" do
    task = tasks(:one)
    original_status_id = task.status_id
    foreign_status = Status.create!(name: "Bespoke", project: projects(:reprioritize_test))

    result = service.run("set_status", { "task_id" => task.id, "status_name" => foreign_status.name })

    assert_match(/No status named/, result[:error])
    assert_equal original_status_id, task.reload.status_id
  end

  test "another user's task is reported as simply not found" do
    other_task = projects(:two).create_task!(title: "Other user's scheduling target", user: users(:two))

    result = service.run("set_scheduled_at", { "task_id" => other_task.id, "scheduled_at" => "2027-03-01T09:00:00Z" })

    assert_equal "Task not found", result[:error]
    assert_nil other_task.reload.scheduled_at
  end

  test "a project excluded from the integration is not writable" do
    excluded_project = Project.create!(title: "Confidential Project", user: @user)
    excluded_task = excluded_project.create_task!(title: "Top secret scheduling target", user: @user)

    scoped = TaskWriteToolsService.new(user: @user, excluded_project_ids: [excluded_project.id])
    result = scoped.run("set_scheduled_at", { "task_id" => excluded_task.id, "scheduled_at" => "2027-03-01T09:00:00Z" })

    assert_equal "Task not found", result[:error]
    assert_nil excluded_task.reload.scheduled_at
  end

  test "an archived task is not writable" do
    task = tasks(:one)
    task.update!(archived: true, archived_at: Time.current)

    result = service.run("set_scheduled_at", { "task_id" => task.id, "scheduled_at" => "2027-03-01T09:00:00Z" })

    assert_equal "Task not found", result[:error]
  end

  test "a write-back is tagged as such in the task's version history" do
    task = tasks(:one)

    service.run("set_scheduled_at", { "task_id" => task.id, "scheduled_at" => "2027-03-01T09:00:00Z" })

    # Task's versions association is scoped `order("id desc")`, so .first is
    # the most recent version.
    assert_equal "api_write_back", task.reload.versions.first.event
  end

  private

  def service
    TaskWriteToolsService.new(user: @user)
  end
end
