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
  end

  test "should be valid" do
    assert @task.valid?
  end

  test "title should be present" do
    @task.title = ""
    assert_not @task.valid?
  end

  test "should have default values" do
    task = Task.new(title: "New Task", user: @user)
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
    task = project.tasks.build(
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

    task = project.tasks.create!(title: "New Task", user: @user)
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
end
