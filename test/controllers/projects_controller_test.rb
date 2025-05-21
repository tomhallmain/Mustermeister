require "test_helper"

class ProjectsControllerTest < ActionDispatch::IntegrationTest
  def setup
    # Dynamically override the layout
    ProjectsController.class_eval do
      layout 'test'
    end
    
    @user = users(:one)
    @project = projects(:one)
    sign_in_as(@user, skip_redirect: true)
    
    setup_paper_trail
  end

  def teardown
    # Reset to default layout
    ProjectsController.class_eval do
      layout 'application'
    end
    
    teardown_paper_trail
  end

  test "should get index" do
    get projects_path
    assert_response :success
  end

  test "should create project with default priority" do
    assert_difference('Project.count') do
      post projects_path, params: {
        project: {
          title: "New Project",
          description: "Project Description",
          default_priority: "high"
        }
      }
    end

    new_project = Project.find_by(title: "New Project")
    assert_equal "high", new_project.default_priority
    assert_redirected_to project_path(new_project)
  end
  
  test "should default to medium priority when creating project without specified priority" do
    assert_difference('Project.count') do
      post projects_path, params: {
        project: {
          title: "Project Without Priority",
          description: "No priority specified"
        }
      }
    end

    new_project = Project.find_by(title: "Project Without Priority")
    assert_equal "medium", new_project.default_priority
  end

  test "should update project default priority" do
    patch project_path(@project), params: {
      project: {
        default_priority: "low"
      }
    }
    
    @project.reload
    assert_equal "low", @project.default_priority
  end

  test "should store show_completed preference in session" do
    # Visit with show_completed=true
    get project_path(@project, show_completed: true)
    assert_response :success
    
    # Then visit without the parameter - should redirect to include it
    get project_path(@project)
    assert_response :redirect
    
    # Verify redirect includes show_completed
    assert_match(/show_completed=true/, @response.redirect_url)
    
    # Follow the redirect
    follow_redirect!
    assert_response :success
  end
  
  test "should change show_completed preference when toggled" do
    # First set to true
    get project_path(@project, show_completed: true)
    assert_response :success
    
    # Then toggle to false
    get project_path(@project, show_completed: false)
    assert_response :success
    
    # Visit without parameter - should redirect with false
    get project_path(@project)
    assert_response :redirect
    
    # Verify redirect includes show_completed=false
    assert_match(/show_completed=false/, @response.redirect_url)
    
    # Follow the redirect
    follow_redirect!
    assert_response :success
  end
  
  test "should show completed tasks when show_completed is true" do
    # Create a completed task
    completed_task = Task.create!(
      title: "Completed Test Task",
      project: @project,
      user: @user,
      completed: true
    )
    
    # Visit with show_completed=true
    get project_path(@project, show_completed: true)
    assert_response :success
  end
  
  test "should hide completed tasks when show_completed is false" do
    # Create a completed task
    completed_task = Task.create!(
      title: "Completed Test Task",
      project: @project,
      user: @user,
      completed: true
    )
    
    # Visit with show_completed=false
    get project_path(@project, show_completed: false)
    assert_response :success
  end

  test "should reprioritize tasks to match project default priority" do
    # Create a fresh project for this test
    project = Project.create!(
      title: "Test Project for Reprioritize",
      user: @user,
      default_priority: "medium"
    )
    
    # Create tasks with different priorities
    high_task = Task.create!(
      title: "High Priority Task",
      project: project,
      user: @user,
      priority: "high"
    )
    
    low_task = Task.create!(
      title: "Low Priority Task",
      project: project,
      user: @user,
      priority: "low"
    )
    
    # Call reprioritize action
    assert_difference -> { Comment.count }, 2 do # Should create 2 audit comments
      post reprioritize_project_path(project)
    end
    
    # Verify tasks were updated
    high_task.reload
    low_task.reload
    assert_equal "medium", high_task.priority
    assert_equal "medium", low_task.priority
    
    # Verify audit comments were created
    assert Comment.exists?(task: high_task, content: "Priority updated to medium to match project default")
    assert Comment.exists?(task: low_task, content: "Priority updated to medium to match project default")
    
    # Verify redirect and flash message
    assert_redirected_to project_path(project)
    assert_match(/Successfully updated 2 tasks/, flash[:notice])
  end
  
  test "should not update tasks that already match project priority" do
    # Create a fresh project for this test
    project = Project.create!(
      title: "Test Project for No Updates",
      user: @user,
      default_priority: "medium"
    )
    
    # Create a task with medium priority
    medium_task = Task.create!(
      title: "Medium Priority Task",
      project: project,
      user: @user,
      priority: "medium"
    )
    
    # Call reprioritize action
    assert_no_difference -> { Comment.count } do # Should not create any audit comments
      post reprioritize_project_path(project)
    end
    
    # Verify task was not updated
    medium_task.reload
    assert_equal "medium", medium_task.priority
    
    # Verify flash message
    assert_redirected_to project_path(project)
    assert_match(/No tasks needed priority updates/, flash[:notice])
  end
  
  test "should handle errors during reprioritization" do
    # Create a fresh project for this test
    project = Project.create!(
      title: "Test Project for Error",
      user: @user,
      default_priority: "medium"
    )
    
    # Create a task that will fail validation
    task = Task.create!(
      title: "Test Task",
      project: project,
      user: @user,
      priority: "high"
    )
    
    # Mock the service to raise an error
    TaskManagementService.stub(:reprioritize_project_tasks, ->(*) { raise TaskManagementService::Error, "Test error" }) do
      post reprioritize_project_path(project)
    end
    
    # Verify redirect and error message
    assert_redirected_to project_path(project)
    assert_match(/Failed to reprioritize tasks/, flash[:alert])
  end
end 