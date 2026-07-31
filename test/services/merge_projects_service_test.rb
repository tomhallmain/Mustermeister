require "test_helper"

class MergeProjectsServiceTest < ActiveSupport::TestCase
  def setup
    @user = users(:one)
    @source = @user.projects.create!(title: "Source Project", description: "src desc", default_priority: "low", color: "red", due_date: Date.tomorrow)
    @target = @user.projects.create!(title: "Target Project", description: "tgt desc", default_priority: "high", color: "blue", due_date: Date.tomorrow + 5)
    setup_paper_trail
  end

  def teardown
    teardown_paper_trail
  end

  test "merges source into target, keeping target's own field values by default" do
    task = @source.tasks.create!(title: "Task A", user: @user)
    comment = @source.comments.create!(user: @user, content: "Project note", status: "open")
    template = @source.recurring_task_templates.create!(
      title: "Water the plants", user: @user, base_unit: "month", interval: 1, start_date: 6.months.ago.to_date
    )

    result = MergeProjectsService.call(source: @source, target: @target, field_choices: {}, current_user: @user)

    assert_equal @target, result
    @target.reload
    assert_equal "Target Project", @target.title
    assert_equal "tgt desc", @target.description
    assert_equal "high", @target.default_priority
    assert_equal "blue", @target.color

    assert_equal @target, task.reload.project
    assert_equal @target, comment.reload.project
    assert_equal @target, template.reload.project
    assert_not Project.exists?(@source.id)
  end

  test "honors per-field choices to keep source's value, falling back to target's for the rest" do
    result = MergeProjectsService.call(
      source: @source,
      target: @target,
      field_choices: { 'title' => 'source', 'default_priority' => 'source' },
      current_user: @user
    )

    result.reload
    assert_equal "Source Project", result.title
    assert_equal "low", result.default_priority
    assert_equal "tgt desc", result.description
    assert_equal "blue", result.color
  end

  test "reconciles a custom status by creating a same-named status on target and remapping the task to it" do
    custom_status = @source.statuses.create!(name: "Blocked")
    task = @source.tasks.create!(title: "Blocked task", user: @user, status: custom_status)

    MergeProjectsService.call(source: @source, target: @target, field_choices: {}, current_user: @user)

    task.reload
    assert_equal @target, task.project
    assert_equal "Blocked", task.status.name
    assert_equal @target, task.status.project
    refute_equal custom_status.id, task.status.id
  end

  test "remaps a default-named status onto target's own matching default status, without duplicating it" do
    in_progress_status = @source.status_by_key(:in_progress)
    task = @source.tasks.create!(title: "In progress task", user: @user, status: in_progress_status)
    target_in_progress = @target.status_by_key(:in_progress)

    MergeProjectsService.call(source: @source, target: @target, field_choices: {}, current_user: @user)

    assert_equal target_in_progress, task.reload.status
  end

  test "moves project-level comments and leaves task-level comments untouched" do
    project_comment = @source.comments.create!(user: @user, content: "Project-level note", status: "open")
    task = @source.tasks.create!(title: "Task with comment", user: @user)
    task_comment = task.comments.create!(user: @user, content: "Task-level note", status: "open")

    MergeProjectsService.call(source: @source, target: @target, field_choices: {}, current_user: @user)

    assert_equal @target, project_comment.reload.project
    assert_nil task_comment.reload.project
    assert_equal task.reload.id, task_comment.task_id
  end

  test "removes the source project id from task_insights_excluded_project_ids" do
    @user.update!(task_insights_excluded_project_ids: [@source.id, 999999])

    MergeProjectsService.call(source: @source, target: @target, field_choices: {}, current_user: @user)

    assert_equal [999999], @user.reload.task_insights_excluded_project_ids
  end

  test "raises when merging a project into itself" do
    error = assert_raises(MergeProjectsService::Error) do
      MergeProjectsService.call(source: @source, target: @source, field_choices: {}, current_user: @user)
    end
    assert_match(/itself/, error.message)
  end

  test "raises when source and target belong to different users" do
    error = assert_raises(MergeProjectsService::Error) do
      MergeProjectsService.call(source: @source, target: projects(:two), field_choices: {}, current_user: @user)
    end
    assert_match(/current user/, error.message)
  end

  test "moves the task instead of destroying it, even when source's tasks association was eager-loaded beforehand" do
    task = @source.tasks.create!(title: "Task A", user: @user)

    # Mirrors ProjectsController#set_project's `includes(:tasks)` - without
    # MergeProjectsService#call reloading source before destroying it, the
    # eager-loaded (and, by the time the merge moves tasks, stale) association
    # cache is what @source.destroy!'s dependent: :destroy would act on,
    # destroying a task that had already been moved to target.
    preloaded_source = Project.includes(:tasks).find(@source.id)

    MergeProjectsService.call(source: preloaded_source, target: @target, field_choices: {}, current_user: @user)

    assert Task.exists?(task.id)
    assert_equal @target, task.reload.project
    assert_not Project.exists?(@source.id)
  end

  test "is atomic - a failure partway through leaves source and its tasks untouched" do
    @source.tasks.create!(title: "Task A", user: @user)

    target = @target
    service = MergeProjectsService.new(@source, target, {}, @user)
    service.define_singleton_method(:apply_field_choices!) { raise ActiveRecord::RecordInvalid.new(target) }

    assert_raises(MergeProjectsService::Error) { service.call }

    assert Project.exists?(@source.id)
    assert_equal 1, @source.reload.tasks.count
  end
end
