require "test_helper"

class TaskSortingTest < ActionDispatch::IntegrationTest
  def setup
    @verbose = false
    @user = users(:sorting_test_user)
    @project = projects(:sorting_test_project)
    
    setup_paper_trail
    
    # Clear any existing tasks for this project to ensure clean state
    @project.tasks.destroy_all
    
    # Create tasks with different timestamps
    base_time = Time.zone.local(2025, 5, 15, 12, 0, 0)
    
    @task1 = @project.tasks.create!(
      title: "Task 1",
      description: "First task",
      user: @user,
      created_at: base_time - 5.days,
      updated_at: base_time - 2.days
    )
    
    @task2 = @project.tasks.create!(
      title: "Task 2",
      description: "Second task",
      user: @user,
      created_at: base_time - 4.days,
      updated_at: base_time  # Most recently updated
    )
    
    @task3 = @project.tasks.create!(
      title: "Task 3",
      description: "Third task",
      user: @user,
      created_at: base_time - 3.days,
      updated_at: base_time  # Same updated_at as Task 2, but created later
    )
    
    @task4 = @project.tasks.create!(
      title: "Task 4",
      description: "Fourth task",
      user: @user,
      created_at: base_time - 2.days,
      updated_at: base_time - 1.day  # Updated yesterday
    )
    
    @task5 = @project.tasks.create!(
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
end 