require "test_helper"

class TaskPaginationTest < ActionDispatch::IntegrationTest
  TASKS_PER_PAGE = TasksController::TASKS_PER_PAGE
  
  def setup
    @user = users(:two)  # Use a different fixture user to avoid conflicts with other tests
    @verbose = false # Enable debug output
    
    setup_paper_trail
    
    # Create a project for the tasks
    @project = @user.projects.create!(
      title: "Test Project",
      description: "Project for pagination tests"
    )
    
    # Create enough tasks to test pagination (16 tasks, which is more than the per_page limit)
    (TASKS_PER_PAGE + 1).times do |i|
      @user.tasks.create!(
        title: "Task #{i + 1}",
        description: "Description for task #{i + 1}",
        completed: i.even?, # Alternate between completed and not completed
        project: @project
      )
    end
    
    # Debug: Print task counts
    debug "Created tasks:"
    debug "Total tasks: #{@user.tasks.count}"
    debug "Completed tasks: #{@user.tasks.completed.count}"
    debug "Non-completed tasks: #{@user.tasks.not_completed.count}"
    
    sign_in_as(@user, skip_redirect: true)
  end
  
  def teardown
    teardown_paper_trail
  end

  test "pagination works with show_completed preference" do
    # First page with completed tasks hidden
    get tasks_path(show_completed: false)
    assert_response :success
    debug "At tasks page with show_completed=false: #{request.path}"
    
    # Debug: Print all task items found
    task_items = css_select(".task-item")
    debug "Found #{task_items.size} task items on first page"
    task_items.each do |task|
      debug "Task: #{task.text.strip}"
    end
    
    assert_equal 8, task_items.size, "Expected 8 non-completed tasks on first page"
    
    # Store the preference in session
    assert_equal false, session[:tasks_show_completed]
    
    # Go to second page
    get tasks_path(show_completed: false, page: 2)
    assert_response :success
    debug "At tasks page with show_completed=false, page=2: #{request.path}"
    
    task_items = css_select(".task-item")
    debug "Found #{task_items.size} task items on second page"
    assert_equal 0, task_items.size, "Expected 0 tasks on second page (all shown on first page)"
    
    # Switch to showing completed tasks
    get tasks_path(show_completed: true)
    assert_response :success
    debug "At tasks page with show_completed=true: #{request.path}"
    
    task_items = css_select(".task-item")
    debug "Found #{task_items.size} task items with completed tasks shown"
    assert_equal TASKS_PER_PAGE, task_items.size, "Expected #{TASKS_PER_PAGE} out of the #{TASKS_PER_PAGE + 1} tasks (both completed and non-completed) on first page"
    
    # Store the new preference
    assert_equal true, session[:tasks_show_completed]
    
    # Go to second page with completed tasks
    get tasks_path(show_completed: true, page: 2)
    assert_response :success
    debug "At tasks page with show_completed=true, page=2: #{request.path}"
    
    task_items = css_select(".task-item")
    debug "Found #{task_items.size} task items on second page with completed tasks"
    assert_equal 1, task_items.size, "Expected 1 task on second page (#{TASKS_PER_PAGE + 1} total tasks, #{TASKS_PER_PAGE} per page)"
  end

  test "pagination preserves show_completed preference" do
    # Set initial preference
    get tasks_path(show_completed: true)
    assert_response :success
    debug "Initial page load with show_completed=true: #{request.path}"
    
    # Debug: Print task counts
    debug "Task counts in database:"
    debug "Total tasks: #{@user.tasks.count}"
    debug "Completed tasks: #{@user.tasks.completed.count}"
    debug "Non-completed tasks: #{@user.tasks.not_completed.count}"
    
    # Click through pages
    get tasks_path(page: 2)
    assert_redirected_to tasks_path(show_completed: true, page: 2)
    debug "Redirected to: #{response.location}"
    
    # Follow redirect while preserving the page parameter
    get response.location
    assert_response :success
    debug "After redirect: #{request.path}"
    
    task_items = css_select(".task-item")
    debug "Found #{task_items.size} task items after redirect"
    assert_equal 1, task_items.size, "Expected 1 task on second page (#{TASKS_PER_PAGE + 1} total tasks, #{TASKS_PER_PAGE} per page)"
    
    # Verify preference is maintained
    assert_equal true, session[:tasks_show_completed]
  end
end 