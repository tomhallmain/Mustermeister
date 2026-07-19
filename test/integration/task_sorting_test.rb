require "test_helper"

class TaskSortingTest < ActionDispatch::IntegrationTest
  def setup
    @verbose = false
    @user = users(:sorting_test_user)
    @project = projects(:sorting_test_project)
    
    setup_paper_trail
    
    # Clear any existing tasks for this project to ensure clean state
    @project.tasks.destroy_all
    
    # Ensure default statuses exist
    @project.create_default_statuses!
    
    # Create tasks with different timestamps
    base_time = Time.zone.local(2025, 5, 15, 12, 0, 0)
    
    @task1 = @project.create_task!(
      title: "Task 1",
      description: "First task",
      user: @user,
      created_at: base_time - 5.days,
      updated_at: base_time - 2.days
    )
    
    @task2 = @project.create_task!(
      title: "Task 2",
      description: "Second task",
      user: @user,
      created_at: base_time - 4.days,
      updated_at: base_time  # Most recently updated
    )
    
    @task3 = @project.create_task!(
      title: "Task 3",
      description: "Third task",
      user: @user,
      created_at: base_time - 3.days,
      updated_at: base_time  # Same updated_at as Task 2, but created later
    )
    
    @task4 = @project.create_task!(
      title: "Task 4",
      description: "Fourth task",
      user: @user,
      created_at: base_time - 2.days,
      updated_at: base_time - 1.day  # Updated yesterday
    )
    
    @task5 = @project.create_task!(
      title: "Task 5",
      description: "Fifth task",
      user: @user,
      created_at: base_time - 1.day,
      updated_at: base_time - 1.day  # Same updated_at as Task 4, but created later
    )
    
    sign_in_as(@user, skip_redirect: true)
  end
  
  def teardown
    teardown_paper_trail
  end

  test "tasks are sorted by updated_at with fallback to created_at" do
    # Visit the project page - expect and follow redirect
    get project_path(@project)
    assert_response :redirect
    debug "Redirected from project page to: #{response.location}"
    follow_redirect!
    assert_response :success
    debug "After redirect - at path: #{request.path}"
    
    # Get all task items
    task_items = css_select(".task-item")
    
    # Extract task titles in the order they appear
    task_titles = task_items.map { |item| item.at_css("h3").text.strip }
    
    # Debug output
    debug "\nTask order in project view:"
    task_titles.each_with_index do |title, index|
      debug "#{index + 1}. #{title}"
    end
    
    # Tasks should be ordered by updated_at (or created_at if updated_at is nil)
    # Task 2 and 3 have same updated_at (base_time), but Task 3 was created later
    # Task 4 and 5 have same updated_at (base_time - 1.day), but Task 5 was created later
    # Task 1 was updated earliest (base_time - 2.days)
    assert_equal "Task 3", task_titles[0]  # Most recently created of the two with same updated_at (base_time)
    assert_equal "Task 2", task_titles[1]  # Less recently created of the two with same updated_at (base_time)
    assert_equal "Task 5", task_titles[2]  # Most recently created of the two with same updated_at (base_time - 1.day)
    assert_equal "Task 4", task_titles[3]  # Less recently created of the two with same updated_at (base_time - 1.day)
    assert_equal "Task 1", task_titles[4]  # Updated earliest
  end

  test "tasks index also sorts by updated_at with fallback to created_at" do
    # Visit the tasks index - expect and follow redirect
    get tasks_path
    assert_response :redirect
    debug "Redirected from tasks index to: #{response.location}"
    follow_redirect!
    assert_response :success
    debug "After redirect - at path: #{request.path}"
    
    # Get all task items
    task_items = css_select(".task-item")
    
    # Extract task titles in the order they appear
    task_titles = task_items.map { |item| item.at_css("h3").text.strip }
    
    # Debug output
    debug "\nTask order in index view:"
    task_titles.each_with_index do |title, index|
      debug "#{index + 1}. #{title}"
    end
    
    # Debug: Print actual timestamps from database
    debug "\nActual timestamps from database:"
    [@task1, @task2, @task3, @task4, @task5].each do |task|
      debug "#{task.title}:"
      debug "  created_at: #{task.created_at}"
      debug "  updated_at: #{task.updated_at}"
    end
    
    # Tasks should be ordered by updated_at (or created_at if updated_at is nil)
    # Task 2 and 3 have same updated_at (base_time), but Task 3 was created later
    # Task 4 and 5 have same updated_at (base_time - 1.day), but Task 5 was created later
    # Task 1 was updated earliest (base_time - 2.days)
    assert_equal "Task 3", task_titles[0]  # Most recently created of the two with same updated_at (base_time)
    assert_equal "Task 2", task_titles[1]  # Less recently created of the two with same updated_at (base_time)
    assert_equal "Task 5", task_titles[2]  # Most recently created of the two with same updated_at (base_time - 1.day)
    assert_equal "Task 4", task_titles[3]  # Less recently created of the two with same updated_at (base_time - 1.day)
    assert_equal "Task 1", task_titles[4]  # Updated earliest
  end

  test "updating a task moves it to the top of the list" do
    # Visit the project page - expect and follow redirect
    get project_path(@project)
    assert_response :redirect
    debug "Redirected from project page to: #{response.location}"
    follow_redirect!
    assert_response :success
    debug "After redirect - at path: #{request.path}"
    
    # Get initial task order
    task_items = css_select(".task-item")
    initial_titles = task_items.map { |item| item.at_css("h3").text.strip }
    
    # Debug output for initial order
    debug "\nInitial task order:"
    initial_titles.each_with_index do |title, index|
      debug "#{index + 1}. #{title}"
    end
    
    # Verify initial order (Task 3 should be first due to created_at being most recent)
    assert_equal "Task 3", initial_titles[0]
    
    # Update Task 1 (which was last in the initial order)
    patch task_path(@task1), params: {
      task: {
        title: "Updated Task 1",
        description: "This task has been updated"
      }
    }
    
    # Visit the project page again - expect and follow redirect
    get project_path(@project)
    assert_response :redirect
    debug "Redirected from project page to: #{response.location}"
    follow_redirect!
    assert_response :success
    debug "After redirect - at path: #{request.path}"
    
    # Get new task order
    task_items = css_select(".task-item")
    new_titles = task_items.map { |item| item.at_css("h3").text.strip }
    
    # Debug output for new order
    debug "\nNew task order after updating Task 1:"
    new_titles.each_with_index do |title, index|
      debug "#{index + 1}. #{title}"
    end
    
    # Task 1 should now be first because it was just updated
    assert_equal "Updated Task 1", new_titles[0]
    
    # Verify that the order has actually changed
    assert_not_equal initial_titles, new_titles, "Task order did not change after update"
    
    # Debug: Print actual timestamps from database after update
    debug "\nActual timestamps from database after update:"
    [@task1, @task2, @task3, @task4, @task5].each do |task|
      debug "#{task.title}:"
      debug "  created_at: #{task.created_at}"
      debug "  updated_at: #{task.updated_at}"
    end
  end

  test "tasks index falls back to the default sort for an unrecognized sort_by value" do
    get tasks_path(show_completed: false, sort_by: 'not_a_real_option')
    assert_response :success

    task_items = css_select(".task-item")
    task_titles = task_items.map { |item| item.at_css("h3").text.strip }

    assert_equal ["Task 3", "Task 2", "Task 5", "Task 4", "Task 1"], task_titles
  end

  test "tasks index sorts active tasks oldest-first then completed tasks newest-first" do
    # update_column bypasses callbacks/timestamps so the carefully-crafted
    # updated_at values from setup are preserved exactly.
    @task2.update_column(:completed, true)
    @task4.update_column(:completed, true)

    get tasks_path(show_completed: true, sort_by: 'active_oldest_completed_newest')
    assert_response :success

    task_items = css_select(".task-item")
    task_titles = task_items.map { |item| item.at_css("h3").text.strip }

    # Active (1, 3, 5): oldest updated_at first -> 1 (-2d), 5 (-1d), 3 (base_time)
    # Completed (2, 4): newest updated_at first -> 2 (base_time), 4 (-1d)
    assert_equal ["Task 1", "Task 5", "Task 3", "Task 2", "Task 4"], task_titles
  end

  test "sort_by persists across pagination links" do
    # setup calls setup_paper_trail before sign_in_as, so the sign-in request
    # clears the request-scoped PaperTrail context; re-establish it before
    # creating records directly here.
    setup_paper_trail
    without_duplicate_title_check do
      (TasksController::TASKS_PER_PAGE + 1).times do |i|
        @project.create_task!(title: "Extra Task #{i}", user: @user)
      end
    end

    get tasks_path(show_completed: false, sort_by: 'active_oldest_completed_newest')
    assert_response :success

    page_two_link = css_select("a[href*='page=2']").first
    assert page_two_link.present?, "Expected a page 2 pagination link once task count exceeds a page"
    assert_includes page_two_link['href'], "sort_by=active_oldest_completed_newest"
  end

  test "sort_by persists in session and applies to a later request that omits it" do
    get tasks_path(show_completed: false, sort_by: 'active_oldest_completed_newest')
    assert_response :success
    assert_equal 'active_oldest_completed_newest', session[:tasks_sort_by]

    get tasks_path(show_completed: false)
    assert_response :success
    assert_equal 'active_oldest_completed_newest', session[:tasks_sort_by]

    selected_option = css_select("select[name='sort_by'] option[selected]").first
    assert_equal 'active_oldest_completed_newest', selected_option['value']
  end

  test "search persists in session and applies to a later request that omits it" do
    get tasks_path(show_completed: false, search: 'Task 1')
    assert_response :success
    assert_equal 'Task 1', session[:tasks_search]

    get tasks_path(show_completed: false)
    assert_response :success
    assert_equal 'Task 1', session[:tasks_search]

    search_field = css_select("input[name='search']").first
    assert_equal 'Task 1', search_field['value']

    task_items = css_select(".task-item")
    task_titles = task_items.map { |item| item.at_css("h3").text.strip }
    assert_equal ["Task 1"], task_titles
  end

  test "explicitly clearing search persists the cleared state" do
    get tasks_path(show_completed: false, search: 'Task 1')
    assert_response :success
    assert_equal 'Task 1', session[:tasks_search]

    get tasks_path(show_completed: false, search: '')
    assert_response :success
    assert_nil session[:tasks_search]

    get tasks_path(show_completed: false)
    assert_response :success
    assert_nil session[:tasks_search]

    task_items = css_select(".task-item")
    assert_equal 5, task_items.size
  end
end 