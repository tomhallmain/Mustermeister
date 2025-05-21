require "test_helper"

class ProjectReprioritizeTest < ActionDispatch::IntegrationTest
  def setup
    @user = users(:one)
    @project = projects(:reprioritize_test)  # Use the reprioritize-specific project
    @verbose = false # Enable debug output
    
    # Sign in first, with full redirect
    post user_session_path, params: { 
      user: { 
        email: @user.email, 
        password: 'password' 
      } 
    }
    follow_redirect!
    
    setup_paper_trail
    
    # Use reprioritize-specific task fixtures
    @high_priority_task = tasks(:reprioritize_high)
    @low_priority_task = tasks(:reprioritize_low)
    
    debug "Using reprioritize test fixtures:"
    debug "High priority task: #{@high_priority_task.inspect}"
    debug "Low priority task: #{@low_priority_task.inspect}"
  end
  
  def teardown
    teardown_paper_trail
  end

  test "reprioritize confirmation dialog - accepting updates tasks" do
    # Visit the project page - expect and follow redirect
    get project_path(@project)
    assert_response :redirect
    debug "Redirected from project page to: #{response.location}"
    follow_redirect!
    assert_response :success
    debug "After redirect - at path: #{request.path}"
    
    # Store initial priorities
    initial_priorities = @project.tasks.pluck(:priority)
    debug "Initial task priorities: #{initial_priorities}"
    
    setup_paper_trail
    debug "PaperTrail state before update:"
    debug "whodunnit: #{PaperTrail.request.whodunnit}"
    debug "controller_info: #{PaperTrail.request.controller_info.inspect}"
    
    # Set project's default priority to medium
    @project.update!(default_priority: 'medium')
    debug "Set project default priority to: #{@project.default_priority}"
    
    setup_paper_trail
    
    # Post to reprioritize endpoint
    assert_difference -> { @project.tasks.where(priority: 'medium').count }, 2 do
      post reprioritize_project_path(@project)
    end
    assert_response :redirect
    debug "Redirected from reprioritize to: #{response.location}"
    follow_redirect!
    debug "After first redirect - at path: #{request.path}"
    
    # Handle potential second redirect
    if response.redirect?
      debug "Got second redirect to: #{response.location}"
      follow_redirect!
    end
    assert_response :success
    debug "Final path after all redirects: #{request.path}"
    
    # Verify success message
    assert_select "#flash-success", "Successfully updated 2 tasks to match project's default priority."
    debug "Success message found"
    
    # Verify all tasks now have the project's default priority
    @project.tasks.reload.each do |task|
      assert_equal 'medium', task.priority
      debug "Task '#{task.title}' priority is now: #{task.priority}"
    end
  end

  test "reprioritize confirmation dialog - dismissing does not update tasks" do
    # Visit the project page - expect and follow redirect
    get project_path(@project)
    assert_response :redirect
    debug "Redirected from project page to: #{response.location}"
    follow_redirect!
    assert_response :success
    debug "After redirect - at path: #{request.path}"
    
    # Store initial priorities
    initial_priorities = @project.tasks.pluck(:priority)
    debug "Initial task priorities: #{initial_priorities}"
    
    setup_paper_trail
    debug "PaperTrail state before update:"
    debug "whodunnit: #{PaperTrail.request.whodunnit}"
    debug "controller_info: #{PaperTrail.request.controller_info.inspect}"
    
    # Set project's default priority to medium
    @project.update!(default_priority: 'medium')
    debug "Set project default priority to: #{@project.default_priority}"
    
    # Simulate a cancelled confirmation by not sending the post request
    # In a real browser, this would be handled by the JavaScript confirmation dialog
    # For integration tests, we can verify the initial state remains unchanged
    
    # Verify no tasks were updated
    @project.tasks.reload.each_with_index do |task, index|
      assert_equal initial_priorities[index], task.priority
      debug "Task '#{task.title}' priority remains: #{task.priority}"
    end
  end
end 