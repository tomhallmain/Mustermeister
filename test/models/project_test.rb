require "test_helper"

class ProjectTest < ActiveSupport::TestCase
  def setup
    @user = users(:one)
    @project = projects(:one)

    # Simulate controller context for PaperTrail
    setup_paper_trail(ip: "192.168.1.1", user_agent: "TestAgent")
  end

  def teardown
    teardown_paper_trail
  end

  test "should be valid" do
    assert @project.valid?
  end

  test "should require title" do
    @project.title = nil
    assert_not @project.valid?
    assert_includes @project.errors[:title], "Title can't be blank"
  end

  test "should require user" do
    @project.user = nil
    assert_not @project.valid?
    assert_includes @project.errors[:user], "must exist"
  end

  test "should validate default_priority inclusion" do
    @project.default_priority = 'invalid'
    assert_not @project.valid?
    assert_includes @project.errors[:default_priority], "must be a valid priority level"
    
    # Valid values should pass
    @project.default_priority = 'low'
    assert @project.valid?
    
    @project.default_priority = 'medium'
    assert @project.valid?
    
    @project.default_priority = 'high'
    assert @project.valid?
    
    @project.default_priority = 'leisure'
    assert @project.valid?
    
    # Nil should be allowed
    @project.default_priority = nil
    assert @project.valid?
  end

  test "should validate color inclusion" do
    @project.color = 'invalid'
    assert_not @project.valid?
    assert_includes @project.errors[:color], "must be a valid color"
    
    # Valid values should pass
    @project.color = 'red'
    assert @project.valid?
    
    @project.color = 'orange'
    assert @project.valid?
    
    @project.color = 'yellow'
    assert @project.valid?
    
    @project.color = 'green'
    assert @project.valid?
    
    @project.color = 'blue'
    assert @project.valid?
    
    @project.color = 'purple'
    assert @project.valid?
    
    @project.color = 'pink'
    assert @project.valid?
    
    @project.color = 'gray'
    assert @project.valid?
    
    # Nil should be allowed
    @project.color = nil
    assert @project.valid?
    
    # Empty string should be allowed
    @project.color = ''
    assert @project.valid?
  end
  
  test "should set medium as default_priority if not specified" do
    # This test verifies that medium is used as a fallback in the Task model
    # when no default_priority is set on the project
    project = Project.create!(title: "No Priority Project", user: @user)
    task = project.create_task!(title: "Task with default priority", user: @user)
    
    assert_equal 'medium', task.priority
  end

  test "should have many tasks" do
    assert_respond_to @project, :tasks
    assert_instance_of Task, @project.tasks.build
  end

  test "should have many comments" do
    assert_respond_to @project, :comments
    assert_instance_of Comment, @project.comments.build
  end

  test "should calculate completion percentage" do
    # Create a new project to avoid fixture interference
    project = Project.create!(title: "Test Project", user: @user)
    project.create_task!(title: "Task 1", completed: true, user: @user)
    project.create_task!(title: "Task 2", completed: false, user: @user)
    
    assert_equal 50, project.completion_percentage
  end

  test "should return 0 completion percentage with no tasks" do
    project = Project.create!(title: "Empty Project", user: @user)
    assert_equal 0, project.completion_percentage
  end

  test "should return 100 completion percentage with all tasks completed" do
    project = Project.create!(title: "Completed Project", user: @user)
    project.create_task!(title: "Task 1", completed: true, user: @user)
    project.create_task!(title: "Task 2", completed: true, user: @user)
    
    assert_equal 100, project.completion_percentage
  end

  test "should set last_activity_at on creation" do
    project = Project.create!(title: "New Project", user: @user)
    assert_not_nil project.last_activity_at
    assert_in_delta Time.current, project.last_activity_at, 1.second
  end

  test "should update last_activity_at when task is updated" do
    project = Project.create!(title: "Test Project", user: @user)
    task = project.create_task!(title: "Test Task", user: @user)
    original_activity = project.last_activity_at
    sleep(1)
    task.update!(title: "Updated Task")
    project.reload
    assert_not_equal original_activity, project.last_activity_at
    assert_in_delta Time.current, project.last_activity_at, 1.second
  end

  test "should destroy associated tasks when destroyed" do
    project = Project.create!(title: "Test Project", user: @user)
    task = project.create_task!(title: "Task", user: @user)
    initial_task_count = Task.count
    
    assert_difference('Task.count', -1) do
      project.destroy
    end
    assert_equal initial_task_count - 1, Task.count
  end

  test "should destroy associated comments when destroyed" do
    project = Project.create!(title: "Test Project", user: @user)
    comment = project.comments.create!(content: "Comment", user: @user)
    initial_comment_count = Comment.count
    
    assert_difference('Comment.count', -1) do
      project.destroy
    end
    assert_equal initial_comment_count - 1, Comment.count
  end

  test "should be searchable by title and description" do
    # Search for "xylo" which should only match our specific test fixtures
    results = Project.where("title ILIKE ? OR description ILIKE ?", "%xylo%", "%xylo%")
    
    # Should find both model search fixtures
    assert_equal 2, results.count
    assert_includes results, projects(:model_search_one)
    assert_includes results, projects(:model_search_two)
  end

  test "completion percentage should be calculated correctly" do
    project = Project.create!(title: "Test Project", user: @user)
    assert_equal 0, project.completion_percentage

    project.create_task!(title: "Task 1", completed: true, user: @user)
    project.create_task!(title: "Task 2", completed: false, user: @user)
    assert_equal 50, project.reload.completion_percentage
  end

  test "status should be completed when all tasks are completed" do
    project = Project.create!(title: "Test Project", user: @user)
    assert_equal "not_started", project.status

    project.create_task!(title: "Task 1", completed: true, user: @user)
    project.create_task!(title: "Task 2", completed: true, user: @user)
    assert_equal "completed", project.reload.status
  end

  test "status should be in_progress when project has incomplete tasks with status other than Not Started" do
    project = Project.create!(title: "Test Project", user: @user)
    in_progress_status = project.status_by_key(:in_progress)
    assert in_progress_status, "Project should have In Progress status from default_statuses"

    project.tasks.create!(title: "Task in progress", completed: false, user: @user, status: in_progress_status)
    assert_equal "in_progress", project.reload.status,
      "Project with an incomplete task in 'In Progress' status should show in_progress, not not_started"
  end

  test "status should be not_started when all incomplete tasks are Not Started and none completed" do
    project = Project.create!(title: "Test Project", user: @user)
    project.create_task!(title: "Task 1", completed: false, user: @user)
    project.create_task!(title: "Task 2", completed: false, user: @user)
    assert_equal "not_started", project.reload.status
  end

  test "should update last_activity_at when task is created" do
    project = Project.create!(title: "Test Project", user: @user)
    initial_activity = project.last_activity_at
    
    travel 1.hour do
      project.create_task!(title: "Test Task", user: @user)
      assert project.reload.last_activity_at > initial_activity
    end
  end

  test "color_classes should return correct CSS classes" do
    @project.color = 'red'
    assert_equal 'border-l-4 border-l-red-500 bg-red-50', @project.color_classes
    
    @project.color = 'blue'
    assert_equal 'border-l-4 border-l-blue-500 bg-blue-50', @project.color_classes
    
    @project.color = nil
    assert_equal '', @project.color_classes
    
    @project.color = ''
    assert_equal '', @project.color_classes
  end

  test "color_badge_classes should return correct CSS classes" do
    @project.color = 'green'
    assert_equal 'bg-green-100 text-green-800 border-green-200', @project.color_badge_classes
    
    @project.color = 'purple'
    assert_equal 'bg-purple-100 text-purple-800 border-purple-200', @project.color_badge_classes
    
    @project.color = nil
    assert_equal '', @project.color_badge_classes
    
    @project.color = ''
    assert_equal '', @project.color_badge_classes
  end

  test "color_display should return human readable color name" do
    @project.color = 'red'
    assert_equal 'Red', @project.color_display
    
    @project.color = 'blue'
    assert_equal 'Blue', @project.color_display
    
    @project.color = nil
    assert_equal 'None', @project.color_display
    
    @project.color = ''
    assert_equal 'None', @project.color_display
  end

  test "should save and retrieve color field" do
    project = Project.new(title: "Color Test Project", user: @user, color: 'green')
    assert project.valid?, "Project should be valid: #{project.errors.full_messages}"
    project.save!
    assert_equal 'green', project.color
    
    project.update!(color: 'purple')
    assert_equal 'purple', project.reload.color
    
    project.update!(color: '')
    assert_equal '', project.reload.color
    
    project.update!(color: nil)
    assert_nil project.reload.color
  end

  test "fixtures should have correct color values" do
    assert_equal 'blue', projects(:one).color
    assert_equal 'red', projects(:two).color
  end

  test "project should have color field" do
    assert @project.respond_to?(:color)
    assert @project.respond_to?(:color=)
  end

  test "database should have color column" do
    columns = Project.column_names
    assert_includes columns, 'color', "Color column should exist in database. Available columns: #{columns.join(', ')}"
  end
end
