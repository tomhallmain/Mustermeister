require "test_helper"

class TaskSearchTest < ActionDispatch::IntegrationTest
  skip "Temporarily skipping this test file"
  include Capybara::DSL

  def setup
    @user = users(:one)  # Use user one to match search fixtures
    @verbose = false # Enable debug output
    
    setup_paper_trail
    
    sign_in_as(@user)
  end
  
  def teardown
    teardown_paper_trail
    Capybara.reset_sessions!
  end

  test "should find tasks by title and description" do
    # Start at tasks index (will redirect to add show_completed param)
    visit tasks_path
    assert_current_path tasks_path(show_completed: false)
    debug "Initial page load: #{current_path}"
    
    # Fill in the search box and click submit
    fill_in "Search", with: "zeb"
    check "Show completed tasks"
    click_button "Search"
    
    # Wait for the page to load after search
    assert_current_path tasks_path(search: "zeb", show_completed: true)
    debug "Search results page: #{current_path}"
    
    # Debug: Print task counts
    debug "Task counts in database:"
    debug "Total tasks: #{@user.tasks.count}"
    debug "Completed tasks: #{@user.tasks.completed.count}"
    debug "Non-completed tasks: #{@user.tasks.not_completed.count}"
    
    # Verify all search results are present
    assert_selector ".task-item", count: 5  # Now includes the completed task
    assert_selector ".task-item", text: /Zebra Task/
    assert_selector ".task-item", text: /My Zebra/
    assert_selector ".task-item", text: /The Amazing Task/
    assert_selector ".task-item", text: /The Great Task/
    assert_selector ".task-item", text: /Completed Zebra Task/
  end

  test "should combine search with show_completed filter" do
    # Start at tasks index (will redirect to add show_completed param)
    visit tasks_path
    assert_current_path tasks_path(show_completed: false)
    debug "Initial page load: #{current_path}"
    
    # Search with completed tasks hidden
    fill_in "Search", with: "zeb"
    uncheck "Show completed tasks"
    click_button "Search"
    
    # Wait for the page to load after search
    assert_current_path tasks_path(search: "zeb", show_completed: false)
    debug "Search with completed tasks hidden: #{current_path}"
    
    # Verify only non-completed tasks are shown
    assert_selector ".task-item", count: 4  # Only non-completed tasks
    
    # Click a task to view its details
    first(".task-item a").click
    assert_response :success
    debug "Task details page: #{current_path}"
    
    # Go back to search results with completed tasks shown
    visit tasks_path
    fill_in "Search", with: "zeb"
    check "Show completed tasks"
    click_button "Search"
    
    # Wait for the page to load after search
    assert_current_path tasks_path(search: "zeb", show_completed: true)
    debug "Search with completed tasks shown: #{current_path}"
    
    # Verify all tasks are shown
    assert_selector ".task-item", count: 5  # All tasks including completed one
    
    # Verify search term and show_completed preference are maintained
    assert_equal true, session[:tasks_show_completed]
  end
end 