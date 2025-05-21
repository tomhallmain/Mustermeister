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
    assert_includes @project.errors[:title], "can't be blank"
  end

  test "should require user" do
    @project.user = nil
    assert_not @project.valid?
    assert_includes @project.errors[:user], "must exist"
  end

  test "should validate default_priority inclusion" do
    @project.default_priority = 'invalid'
    assert_not @project.valid?
    assert_includes @project.errors[:default_priority], "is not included in the list"
    
    # Valid values should pass
    @project.default_priority = 'low'
    assert @project.valid?
    
    @project.default_priority = 'medium'
    assert @project.valid?
    
    @project.default_priority = 'high'
    assert @project.valid?
    
    # Nil should be allowed
    @project.default_priority = nil
    assert @project.valid?
  end
  
  test "should set medium as default_priority if not specified" do
    # This test verifies that medium is used as a fallback in the Task model
    # when no default_priority is set on the project
    project = Project.create!(title: "No Priority Project", user: @user)
    task = project.tasks.create!(title: "Task with default priority", user: @user)
    
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
    project.tasks.create!(title: "Task 1", completed: true, user: @user)
    project.tasks.create!(title: "Task 2", completed: false, user: @user)
    
    assert_equal 50, project.completion_percentage
  end

  test "should return 0 completion percentage with no tasks" do
    project = Project.create!(title: "Empty Project", user: @user)
    assert_equal 0, project.completion_percentage
  end

  test "should return 100 completion percentage with all tasks completed" do
    project = Project.create!(title: "Completed Project", user: @user)
    project.tasks.create!(title: "Task 1", completed: true, user: @user)
    project.tasks.create!(title: "Task 2", completed: true, user: @user)
    
    assert_equal 100, project.completion_percentage
  end

  test "should set last_activity_at on creation" do
    project = Project.create!(title: "New Project", user: @user)
    assert_not_nil project.last_activity_at
    assert_in_delta Time.current, project.last_activity_at, 1.second
  end

  test "should update last_activity_at when task is updated" do
    project = Project.create!(title: "Test Project", user: @user)
    task = project.tasks.create!(title: "Test Task", user: @user)
    original_activity = project.last_activity_at
    sleep(1)
    task.update!(title: "Updated Task")
    project.reload
    assert_not_equal original_activity, project.last_activity_at
    assert_in_delta Time.current, project.last_activity_at, 1.second
  end

  test "should destroy associated tasks when destroyed" do
    project = Project.create!(title: "Test Project", user: @user)
    task = project.tasks.create!(title: "Task", user: @user)
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
end
