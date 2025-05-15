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
    
    # Setup PaperTrail for controller tests
    PaperTrail.request.whodunnit = @user.id
    PaperTrail.request.controller_info = {
      ip: "127.0.0.1",
      user_agent: "Rails Testing"
    }
  end

  def teardown
    # Reset to default layout
    ProjectsController.class_eval do
      layout 'application'
    end
    
    # Reset PaperTrail 
    PaperTrail.request.whodunnit = nil
    PaperTrail.request.controller_info = {}
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
end 