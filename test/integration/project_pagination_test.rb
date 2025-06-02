require "test_helper"

class ProjectPaginationTest < ActionDispatch::IntegrationTest
  TASKS_PER_PAGE = ProjectsController::TASKS_PER_PAGE

  def setup
    @user = users(:two)  # Use a different fixture user to avoid conflicts with other tests
    @project = projects(:two)  # Use a different fixture project to avoid conflicts with other tests
    @verbose = false # Enable debug output
    
    setup_paper_trail
    
    # Create enough tasks to test pagination (one more than the per_page limit)
    (TASKS_PER_PAGE + 1).times do |i|
      @project.tasks.create!(
        title: "Task #{i + 1}",
        description: "Description for task #{i + 1}",
        user: @user,
        completed: i.even? # Alternate between completed and not completed
      )
    end
    
    # Debug: Print task counts
    debug "Created tasks:"
    debug "Total tasks: #{@project.tasks.count}"
    debug "Completed tasks: #{@project.tasks.completed.count}"
    debug "Non-completed tasks: #{@project.tasks.not_completed.count}"
    
    sign_in_as(@user, skip_redirect: true)
  end
  
  def teardown
    teardown_paper_trail
  end

  test "default priority is displayed correctly" do
    get project_path(@project)
    assert_redirected_to project_path(@project, show_completed: false)
    
    # Follow the redirect
    get response.location
    assert_response :success
    
    # Find the priority tag
    priority_tag = css_select("span:contains('#{@project.default_priority.capitalize}')").first
    assert_not_nil priority_tag, "Priority tag not found"
    
    # Verify the correct CSS classes are applied based on priority
    expected_classes = case @project.default_priority
                      when 'high' then 'bg-red-100 text-red-800'
                      when 'medium' then 'bg-yellow-100 text-yellow-800'
                      else 'bg-green-100 text-green-800'
                      end
    
    assert_includes priority_tag['class'], expected_classes, "Priority tag has incorrect styling"
  end

  test "pagination works with show_completed preference" do
    # First page with completed tasks hidden
    get project_path(@project, show_completed: false)
    assert_response :success
    debug "At project page with show_completed=false: #{request.path}"
    
    # Debug: Print all task items found
    task_items = css_select(".task-item")
    debug "Found #{task_items.size} task items on first page"
    # task_items.each do |task|
    #   debug "Task: #{task.text.strip}"
    # end
    
    assert_equal 8, task_items.size, "Expected 8 non-completed tasks on first page"
    
    # Store the preference in session
    assert_equal false, session[:projects_show_completed][@project.id.to_s]
    
    # Go to second page
    get project_path(@project, show_completed: false, page: 2)
    assert_response :success
    debug "At project page with show_completed=false, page=2: #{request.path}"
    
    task_items = css_select(".task-item")
    debug "Found #{task_items.size} task items on second page"
    assert_equal 0, task_items.size, "Expected 0 tasks on second page (all shown on first page)"
    
    # Switch to showing completed tasks
    get project_path(@project, show_completed: true)
    assert_response :success
    debug "At project page with show_completed=true: #{request.path}"
    
    task_items = css_select(".task-item")
    debug "Found #{task_items.size} task items with completed tasks shown"
    assert_equal TASKS_PER_PAGE, task_items.size, "Expected #{TASKS_PER_PAGE} out of the #{TASKS_PER_PAGE + 1} tasks (both completed and non-completed) on first page"
    
    # Store the new preference
    assert_equal true, session[:projects_show_completed][@project.id.to_s]
    
    # Go to second page with completed tasks
    get project_path(@project, show_completed: true, page: 2)
    assert_response :success
    debug "At project page with show_completed=true, page=2: #{request.path}"
    
    task_items = css_select(".task-item")
    debug "Found #{task_items.size} task items on second page with completed tasks"
    assert_equal 1, task_items.size, "Expected 1 task on second page (#{TASKS_PER_PAGE + 1} total tasks, #{TASKS_PER_PAGE} per page)"
  end

  test "pagination preserves show_completed preference" do
    # Set initial preference
    get project_path(@project, show_completed: true)
    assert_response :success
    debug "Initial page load with show_completed=true: #{request.path}"
    
    # Debug: Print task counts
    debug "Task counts in database:"
    debug "Total tasks: #{@project.tasks.count}"
    debug "Completed tasks: #{@project.tasks.completed.count}"
    debug "Non-completed tasks: #{@project.tasks.not_completed.count}"
    
    # Click through pages
    get project_path(@project, page: 2)
    assert_redirected_to project_path(@project, show_completed: true, page: 2)
    debug "Redirected to: #{response.location}"
    
    # Follow redirect while preserving the page parameter
    get response.location
    assert_response :success
    debug "After redirect: #{request.path}"
    
    task_items = css_select(".task-item")
    debug "Found #{task_items.size} task items after redirect"
    assert_equal 1, task_items.size, "Expected 1 task on second page (#{TASKS_PER_PAGE + 1} total tasks, #{TASKS_PER_PAGE} per page)"
    
    # Verify preference is maintained
    assert_equal true, session[:projects_show_completed][@project.id.to_s]
  end

  test "search functionality works with relevance ordering" do
    # Search for "muse"
    get projects_path(search: "muse")
    assert_response :success
    
    # Get all project titles in order
    project_titles = css_select(".text-base.font-semibold").map(&:text)
    
    # Verify ordering:
    # 1. "Museum Project" should be first (starts with search term)
    assert_equal "Museum Project", project_titles.first.strip
    # 2. "My Museum" should be second (search term at start of a word)
    assert_equal "My Museum", project_titles[1].strip
    # 3. "The Amazing Project" and "The Great Project" should be last (search term only in description)
    assert_includes ["The Amazing Project", "The Great Project"], project_titles[2].strip
    assert_includes ["The Amazing Project", "The Great Project"], project_titles[3].strip
    assert_not_equal project_titles[2], project_titles[3], "Should have different projects in last two positions"
  end
end 