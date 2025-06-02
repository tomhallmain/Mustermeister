require "test_helper"

class TaskSearchTest < ActionDispatch::IntegrationTest
  def setup
    @user = users(:one)  # Use user one to match search fixtures
    @verbose = false # Enable debug output
    
    setup_paper_trail
    
    sign_in_as(@user, skip_redirect: true)
  end
  
  def teardown
    teardown_paper_trail
  end

  test "search results are paginated correctly" do
    # First page of search results (all tasks visible)
    get tasks_path(search: "zeb", show_completed: true)
    assert_response :success
    debug "First page of search results: #{request.path}"
    
    task_items = css_select(".task-item")
    debug "Found #{task_items.size} task items on first page"
    assert_equal 5, task_items.size, "Expected 5 search test fixtures on first page"
    
    # Search with completed tasks hidden
    get tasks_path(search: "zeb", show_completed: false)
    assert_response :success
    debug "Search results with completed tasks hidden: #{request.path}"
    
    task_items = css_select(".task-item")
    debug "Found #{task_items.size} task items with completed tasks hidden"
    assert_equal 4, task_items.size, "Expected 4 tasks when completed tasks are hidden"
    
    # Verify search parameters are preserved in the current URL
    assert_select "form[action='#{tasks_path}']" do
      assert_select "input[name='search'][value='zeb']"
      assert_select "input[name='show_completed']"
    end
  end
end 