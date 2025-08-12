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
    @project.create_default_statuses!  # Ensure default statuses are created
    sign_in_as(@user, skip_redirect: true)
    
    setup_paper_trail
  end

  def teardown
    # Reset to default layout
    TasksController.class_eval do
      layout 'application'
    end
    
    teardown_paper_trail
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

  test "should create task with default status" do
    assert_difference('Task.count') do
      post tasks_path, params: {
        task: {
          title: "New Task",
          description: "Task Description",
          project_id: @project.id
        }
      }
    end

    task = Task.last
    assert_equal "Not Started", task.status.name
    assert_redirected_to project_path(task.project, show_completed: false)
  end

  test "should create task with specified status" do
    status = @project.status_by_key(:in_progress)
    assert_difference('Task.count') do
      post tasks_path, params: {
        task: {
          title: "New Task",
          description: "Task Description",
          project_id: @project.id,
          status_id: status.id
        }
      }
    end

    task = Task.last
    assert_equal "In Progress", task.status.name
    assert_redirected_to project_path(task.project, show_completed: false)
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

  test "kanban_tasks should include project color in JSON response" do
    # Ensure project has a color set
    @project.update!(color: 'green')
    
    # Debug: Check if the project actually has the color set
    @project.reload
    assert_equal 'green', @project.color, "Project color should be 'green'"
    
    get kanban_tasks_path, as: :json
    assert_response :success
    
    json_response = JSON.parse(response.body)
    assert_includes json_response.keys, 'tasks'
    
    # Check that tasks include project_color
    # Only check tasks that belong to our updated project
    json_response['tasks'].each do |status, tasks|
      tasks.each do |task|
        assert_includes task.keys, 'project_color'
        # Only assert the color for tasks from our specific project
        if task['project'] == @project.title
          assert_equal 'green', task['project_color'], "Expected project_color to be 'green' for project '#{@project.title}', got '#{task['project_color']}'"
        end
      end
    end
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

  test "should update task with new status" do
    new_status = @project.status_by_key(:ready_to_test)
    assert_not_nil new_status, "Ready to Test status should exist"
    
    patch task_path(@task), params: {
      task: {
        status_id: new_status.id
      }
    }
    assert_redirected_to project_path(@task.project, show_completed: false)
    @task.reload
    assert_equal "Ready to Test", @task.status.name
  end

  test "should maintain status when updating other fields" do
    original_status = @task.status
    patch task_path(@task), params: {
      task: {
        title: "Updated Title",
        description: "Updated Description"
      }
    }
    assert_redirected_to project_path(@task.project, show_completed: false)
    @task.reload
    assert_equal original_status, @task.status
  end

  test "should handle invalid status id gracefully" do
    original_status = @task.status
    
    patch task_path(@task), params: {
      task: {
        status_id: 999999  # Non-existent status ID
      }
    }
    
    # Should redirect back to the project page
    assert_redirected_to project_path(@task.project, show_completed: false)
    
    # Status should remain unchanged
    @task.reload
    assert_equal original_status, @task.status
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
    assert_equal "Complete", @task.status.name
  end

  test "should archive task" do
    post archive_task_path(@task)
    assert_redirected_to tasks_path(show_completed: false)
    @task.reload
    assert @task.archived
  end

  test "should search tasks by title and description" do
    # Search for "zeb" which should match our search test fixtures
    get tasks_path(search: "zeb", show_completed: false)
    assert_response :success
    
    # Verify all search results are present
    assert_select ".task-item", 4
    assert_select ".task-item", text: /Zebra Task/
    assert_select ".task-item", text: /My Zebra/
    assert_select ".task-item", text: /The Amazing Task/
    assert_select ".task-item", text: /The Great Task/
  end

  test "should combine search with show_completed filter" do
    # Mark one of the search tasks as completed
    tasks(:search_test_one).update!(completed: true)
    
    # Search with completed tasks hidden
    get tasks_path(search: "zeb", show_completed: false)
    assert_response :success
    assert_select ".task-item", 3
    
    # Search with completed tasks shown
    get tasks_path(search: "zeb", show_completed: true)
    assert_response :success
    assert_select ".task-item", 5
  end

  test "should set status to complete when creating task with completed checkbox" do
    assert_difference('Task.count') do
      post tasks_path, params: {
        task: {
          title: "Completed Task",
          description: "This task is completed",
          project_id: @project.id,
          completed: true
        }
      }
    end

    task = Task.last
    assert_equal Status.find_by(name: Status.default_statuses[:complete]), task.status
    assert task.completed?
    assert task.complete?
  end
end 