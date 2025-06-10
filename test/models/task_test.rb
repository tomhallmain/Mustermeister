require "test_helper"

class TaskTest < ActiveSupport::TestCase
  def setup
    @user = users(:one)
    @project = projects(:one)
    @task = Task.new(
      title: "Test Task",
      description: "Test Description",
      user: @user,
      project: @project
    )
    @status = @project.status_by_key(:not_started)
    @task.status = @status
    setup_paper_trail
  end

  def teardown
    teardown_paper_trail
  end

  test "should be valid" do
    assert @task.valid?
  end

  test "title should be present" do
    @task.title = ""
    assert_not @task.valid?
  end

  test "priority should be valid" do
    @task.priority = "invalid"
    assert_not @task.valid?
    
    # Test valid priorities
    @task.priority = "low"
    assert @task.valid?
    
    @task.priority = "medium"
    assert @task.valid?
    
    @task.priority = "high"
    assert @task.valid?
    
    @task.priority = "leisure"
    assert @task.valid?
  end

  test "priority can be nil" do
    @task.priority = nil
    assert @task.valid?
  end

  test "status should belong to same project" do
    other_project = projects(:two)
    other_status = Status.new(name: "Other Status", project: other_project)
    @task.status = other_status
    assert_not @task.valid?
    assert_includes @task.errors[:status], "must belong to the same project"
  end

  test "status helper methods work correctly" do
    Status.default_statuses.each do |key, name|
      @task.status = Status.new(name: name, project: @project)
      assert @task.send("#{key}?"), "Expected #{key}? to be true for status '#{name}'"
    end
  end

  test "status helper methods return false for non-matching statuses" do
    @task.status = Status.new(name: "Custom Status", project: @project)
    assert_not @task.not_started?
    assert_not @task.in_progress?
    assert_not @task.complete?
  end

  test "sets default status to not_started" do
    new_task = Task.new(
      title: "New Task",
      project: @project,
      user: @user
    )
    assert_nil new_task.status
    new_task.save!
    assert_equal Status.default_statuses[:not_started], new_task.status.name
  end

  test "mark_as_complete! sets correct attributes" do
    @task.mark_as_complete!(@user)
    assert @task.completed
    assert_not_nil @task.completed_at
    assert_equal @user.id, @task.completed_by
    assert_equal Status.default_statuses[:complete], @task.status.name
  end

  test "mark_as_complete! closes open comments" do
    @task.save!
    comment = @task.comments.create!(
      content: "Test comment",
      user: @user,
      status: 'open'
    )
    @task.mark_as_complete!(@user)
    assert_equal 'closed', comment.reload.status
  end

  test "bulk_update_status updates multiple tasks" do
    @task.save!
    other_task = Task.create!(
      title: "Other Task",
      description: "Other Description",
      user: @user,
      project: @project
    )
    new_status = Status.new(name: "New Status", project: @project)
    new_status.save!

    Task.bulk_update_status([@task.id, other_task.id], new_status.id, @user)
    
    [@task, other_task].each do |task|
      assert_equal new_status, task.reload.status
    end
  end

  test "should have default values" do
    task = Task.new(title: "New Task", user: @user, project: @project)
    assert_equal false, task.completed
    assert_equal 'medium', task.priority
    assert_equal false, task.archived
  end

  test "should override project default priority when explicitly set" do
    # Create a project with high default priority
    project = Project.create!(
      title: "High Priority Project", 
      user: @user,
      default_priority: 'high'
    )
    
    # Create a task with explicit low priority
    task = project.build_task(
      title: "Low Priority Task", 
      user: @user,
      priority: 'low'
    )
    task.save!
    
    # Task priority should be the explicitly set value, not the project default
    assert_equal 'low', task.priority
  end

  test "completion percentage should be calculated correctly" do
    # Create a new project with a single task
    project = Project.create!(title: "Test Project", user: @user)
    assert_equal 0, project.completion_percentage

    task = project.create_task!(
      title: "New Task", 
      user: @user
    )
    assert_equal 0, project.reload.completion_percentage

    task.update!(completed: true)
    assert_equal 100, project.reload.completion_percentage
  end

  test "should archive task and close comments" do
    # Create a new task with a single comment
    task = Task.create!(
      title: "Test Task",
      user: @user,
      project: @project
    )
    comment = task.comments.create!(content: "Test comment", user: @user, status: 'open')
    initial_closed_count = task.comments.where(status: 'closed').count
    
    # Archive should close the existing comment and create an archive note
    assert_difference -> { task.comments.where(status: 'closed').count }, 2 do
      task.archive!(@user)
    end
    
    assert task.archived?
    assert_not_nil task.archived_at
    assert_equal @user.id, task.archived_by
  end

  test "should allow deletion when comments are resolved or closed" do
    # Create a new task
    task = Task.create!(
      title: "Test Task",
      user: @user,
      project: @project
    )
    initial_task_count = Task.count
    
    # Add some resolved and closed comments
    task.comments.create!(
      content: "Resolved comment",
      user: @user,
      status: 'resolved'
    )
    task.comments.create!(
      content: "Closed comment",
      user: @user,
      status: 'closed'
    )
    
    # Verify we can delete the task
    assert_difference 'Task.count', -1 do
      task.destroy
    end
    
    # Verify the task and its comments are gone
    assert_nil Task.find_by(id: task.id)
    assert_empty Comment.where(task_id: task.id)
  end

  test "should be searchable by title and description" do
    # Search for "zeb" which should only match our specific test fixtures
    results = Task.where("title ILIKE ? OR description ILIKE ?", "%zeb%", "%zeb%")
    
    # Should find all four search test fixtures
    assert_equal 5, results.count
    assert_includes results, tasks(:search_test_one)
    assert_includes results, tasks(:search_test_two)
    assert_includes results, tasks(:search_test_three)
    assert_includes results, tasks(:search_test_four)
  end
end
