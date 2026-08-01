require "test_helper"

class TaskMergeServiceTest < ActiveSupport::TestCase
  def setup
    @user = users(:one)
    @project = projects(:one)
    setup_paper_trail(@user)
    @target = @project.tasks.create!(title: "Short", description: "tgt desc", priority: "low", due_date: Date.tomorrow + 5, user: @user, skip_duplicate_check: true)
    @source = @project.tasks.create!(title: "A much longer title", description: "src desc", priority: "high", due_date: Date.tomorrow, user: @user, skip_duplicate_check: true)
  end

  def teardown
    teardown_paper_trail
  end

  test "merges source into target - longer title, concatenated description, higher priority, earlier due date" do
    result = TaskMergeService.call(target: @target, source: @source, current_user: @user)

    assert_equal @target, result
    @target.reload
    assert_equal "A much longer title", @target.title
    assert_equal "tgt desc\n\n--- Merged from \"A much longer title\" ---\nsrc desc", @target.description
    assert_equal "high", @target.priority
    assert_equal Date.tomorrow, @target.due_date
    assert_not Task.exists?(@source.id)
  end

  test "falls back to source's task_category only if target has none" do
    category = task_categories(:feature)
    @source.update!(task_category: category)

    TaskMergeService.call(target: @target, source: @source, current_user: @user)

    assert_equal category, @target.reload.task_category
  end

  test "keeps target's own task_category when both have one" do
    @target.update!(task_category: task_categories(:feature))
    @source.update!(task_category: task_categories(:fix))

    TaskMergeService.call(target: @target, source: @source, current_user: @user)

    assert_equal task_categories(:feature), @target.reload.task_category
  end

  test "unions tags from both tasks" do
    @target.tag_ids = [tags(:one).id]
    @target.save!
    @source.tag_ids = [tags(:two).id]
    @source.save!

    TaskMergeService.call(target: @target, source: @source, current_user: @user)

    assert_equal [tags(:one).id, tags(:two).id].sort, @target.reload.tag_ids.sort
  end

  test "moves all of source's comments to target" do
    comment = @source.comments.create!(user: @user, content: "Source note", status: "open")

    TaskMergeService.call(target: @target, source: @source, current_user: @user)

    assert_equal @target.id, comment.reload.task_id
  end

  test "moves all of source's attachments to target" do
    file = StringIO.new("hello world")
    file.define_singleton_method(:original_filename) { "notes.txt" }
    attachment = Attachment.create!(task: @source, user: @user, file: file)

    TaskMergeService.call(target: @target, source: @source, current_user: @user)

    assert_equal @target.id, attachment.reload.task_id
  end

  test "inherits source's task_result only if target has none" do
    @source.update!(completed: true) # auto-creates source's task_result via sync_task_result_with_completion
    result = @source.reload.task_result

    # sync_task_result_with_completion always auto-creates a task_result for
    # a completed task on any normal save, so "completed with no result yet"
    # can't be reached through the normal update path - forcing it via
    # update_column to exercise TaskMergeService's own defensive handling of
    # that state directly.
    @target.update_column(:completed, true)

    TaskMergeService.call(target: @target, source: @source, current_user: @user)

    assert_equal @target.id, result.reload.task_id
  end

  test "keeps target's own task_result when both have one" do
    @target.update!(completed: true)
    @source.update!(completed: true)
    target_result = @target.reload.task_result

    TaskMergeService.call(target: @target, source: @source, current_user: @user)

    assert_equal target_result, @target.reload.task_result
  end

  test "inherits source's recurring_task_template only if target has none" do
    template = RecurringTaskTemplate.create!(
      title: "Water the plants", project: @project, user: @user, base_unit: "month", interval: 1, start_date: 6.months.ago.to_date
    )
    @source.update!(recurring_task_template: template)

    TaskMergeService.call(target: @target, source: @source, current_user: @user)

    assert_equal template, @target.reload.recurring_task_template
  end

  test "tags the target's latest version with the merged paper_trail_event" do
    TaskMergeService.call(target: @target, source: @source, current_user: @user)

    # Task's versions association is scoped `order("id desc")`, so .first -
    # not .last - is the most recent version.
    assert_equal "merged", @target.versions.first.event
  end

  test "raises when merging a task into itself" do
    error = assert_raises(TaskMergeService::Error) do
      TaskMergeService.call(target: @target, source: @target, current_user: @user)
    end
    assert_match(/itself/, error.message)
  end

  test "raises when target and source belong to different users" do
    other_task = projects(:two).tasks.create!(title: "Other user's task", user: users(:two))

    error = assert_raises(TaskMergeService::Error) do
      TaskMergeService.call(target: @target, source: other_task, current_user: @user)
    end
    assert_match(/belong to you/, error.message)
  end

  test "raises when target and source are in different projects" do
    other_project = @user.projects.create!(title: "Other Project")
    other_task = other_project.tasks.create!(title: "Task in other project", user: @user)

    error = assert_raises(TaskMergeService::Error) do
      TaskMergeService.call(target: @target, source: other_task, current_user: @user)
    end
    assert_match(/same project/, error.message)
  end

  test "moves the comment instead of destroying it, even when source's comments association was eager-loaded beforehand" do
    comment = @source.comments.create!(user: @user, content: "Source note", status: "open")

    # Mirrors TasksController's plain Task.find - without TaskMergeService#call
    # reloading source before destroying it, the eager-loaded (and, by the
    # time the merge moves comments, stale) association cache is what
    # @source.destroy!'s dependent: :destroy would act on, destroying a
    # comment that had already been moved to target.
    preloaded_source = Task.includes(:comments).find(@source.id)

    TaskMergeService.call(target: @target, source: preloaded_source, current_user: @user)

    assert Comment.exists?(comment.id)
    assert_equal @target.id, comment.reload.task_id
  end

  test "is atomic - a failure partway through leaves source and its comments untouched" do
    @source.comments.create!(user: @user, content: "Source note", status: "open")

    target = @target
    service = TaskMergeService.new(target, @source, @user)
    service.define_singleton_method(:merge_task_result!) { raise ActiveRecord::RecordInvalid.new(target) }

    assert_raises(TaskMergeService::Error) { service.call }

    assert Task.exists?(@source.id)
    assert_equal 1, @source.reload.comments.count
  end
end
