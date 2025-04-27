require "test_helper"

class ProjectTest < ActiveSupport::TestCase
  def setup
    @user = users(:one)
    @project = projects(:one)

    # Simulate controller context for PaperTrail
    PaperTrail.request.whodunnit = @user.id
    PaperTrail.request.controller_info = {
      ip: "192.168.1.1",
      user_agent: "TestAgent"
    }
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
