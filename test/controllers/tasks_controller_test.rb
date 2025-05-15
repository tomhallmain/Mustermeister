require "test_helper"

class TasksControllerTest < ActionDispatch::IntegrationTest
  def setup
    # Dynamically override the layout for TasksController
    TasksController.class_eval do
      layout 'test'
    end
    
    @user = users(:one)
    @project = projects(:one)
    @task = tasks(:one)
    sign_in_as(@user, skip_redirect: true)
    
    # Setup PaperTrail for controller tests
    PaperTrail.request.whodunnit = @user.id
    PaperTrail.request.controller_info = {
      ip: "127.0.0.1",
      user_agent: "Rails Testing"
    }
  end

  def teardown
    # Reset to default layout
    TasksController.class_eval do
      layout 'application'
    end
    
    # Reset PaperTrail 
    PaperTrail.request.whodunnit = nil
    PaperTrail.request.controller_info = {}
  end

  test "should get index" do
    # The index action now redirects to add show_completed param if missing
    get tasks_path(show_completed: false)
    assert_response :success
    assert_select "h1", "Tasks"
  end

  test "should redirect to tasks when trying to create task without project" do
    get new_task_path
    assert_redirected_to tasks_path(show_completed: false)
  end

  test "should create task" do
    assert_difference('Task.count') do
      post tasks_path, params: {
        task: {
          title: "New Task",
          description: "Task Description",
          project_id: @project.id
        }
      }
    end

    assert_redirected_to project_path(Task.last.project, show_completed: false)
  end

  test "should use specified priority when creating task" do
    # Set a default priority on the project
    @project.update!(default_priority: 'high')
    
    # Create the task with explicit low priority
    assert_difference('Task.count') do
      post tasks_path, params: {
        task: {
          title: "Low Priority Task",
          description: "This should use explicit low priority",
          project_id: @project.id,
          priority: 'low'
        }
      }
    end
    
    # Verify the task got the explicit priority, not project default
    task = Task.find_by(title: "Low Priority Task")
    assert_equal 'low', task.priority
  end

  test "should show task" do
    get task_path(@task)
    assert_response :success
  end

  test "should get edit" do
    get edit_task_path(@task)
    assert_response :success
  end

  test "should update task" do
    patch task_path(@task), params: {
      task: {
        title: "Updated Task",
        description: "Updated Description"
      }
    }
    assert_redirected_to project_path(@task.project, show_completed: false)
    @task.reload
    assert_equal "Updated Task", @task.title
  end

  test "should destroy task" do
    assert_difference('Task.count', -1) do
      delete task_path(@task)
    end

    assert_redirected_to project_path(@task.project, show_completed: false)
  end

  test "should toggle task completion" do
    patch toggle_task_path(@task)
    assert_redirected_to tasks_path(show_completed: false)
    @task.reload
    assert @task.completed
  end

  test "should archive task" do
    post archive_task_path(@task)
    assert_redirected_to tasks_path(show_completed: false)
    @task.reload
    assert @task.archived
  end
end 