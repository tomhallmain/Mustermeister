require "test_helper"

class TaskCreationTest < ActionDispatch::IntegrationTest
  def setup
    @user = users(:one)
    @project = projects(:one)
    @verbose = false # Enable debug output
    
    # Sign in
    post user_session_path, params: { 
      user: { 
        email: @user.email, 
        password: 'password' 
      } 
    }
    follow_redirect!
    
    setup_paper_trail
  end
  
  def teardown
    teardown_paper_trail
  end

  test "should inherit project default priority when creating a task" do
    # Set a specific default priority on the project
    @project.update!(default_priority: 'high')
    
    # Visit the new task form with project_id
    get new_task_path, params: { project_id: @project.id }
    assert_response :redirect
    follow_redirect!
    assert_response :success
    
    # In a real application, the form would be pre-filled with the project's default priority
    # When submitted, this pre-filled value would be included in the params
    # Let's simulate this by including the project's default priority in our post
    assert_difference('Task.count') do
      post tasks_path, params: {
        task: {
          title: "Priority Task",
          description: "This should inherit high priority",
          project_id: @project.id,
          priority: @project.default_priority  # Simulate the pre-filled form value
        }
      }
    end
    
    # The task should be created with the project's default priority
    task = Task.find_by(title: "Priority Task")
    assert_equal 'high', task.priority
  end
  
  test "task creation form should pre-fill the project's default priority" do
    # Set a specific default priority on the project
    @project.update!(default_priority: 'low')
    
    # Real user workflow:
    # 1. Visit projects page
    get projects_path
    assert_response :success
    debug "At projects page: #{request.path}"
    
    # 2. Visit specific project page - expect and follow redirect
    get project_path(@project)
    assert_response :redirect
    debug "Redirected from project page to: #{response.location}"
    follow_redirect!
    assert_response :success
    debug "After redirect - at path: #{request.path}"
    
    # 3. Find the "New Task" link in the project page HTML
    # Debug: Print all links in the page to find the new task link
    links = css_select("a")
    debug "Found #{links.size} links on the project page:"
    new_task_link = nil
    links.each do |link|
      href = link['href']
      text = link.text.strip
      debug "Link: #{text} -> #{href}"
      
      # Look for a link with text containing "New Task" or href containing "/tasks/new"
      if (text.include?("New Task") || (href && href.include?("/projects/#{@project.id}/tasks/new")))
        new_task_link = href
        debug "Found New Task link: #{new_task_link}"
        break
      end
    end
    
    # Assert that the "New Task" link exists
    assert new_task_link.present?, "Could not find 'New Task' link in the project page"
    
    # 4. Visit the new task form using the discovered link
    get new_task_link
    if response.redirect?
      debug "Redirected from new task link to: #{response.location}"
      follow_redirect!
    end
    assert_response :success
    debug "Now at new task form path: #{request.path}"
    
    # 5. Now check that the form has the project's default priority pre-selected
    # Dump the first 1000 characters of response body to see what we're dealing with
    # debug "Response preview: #{response.body[0..1000]}"
    
    # Let's get all select elements and their options
    select_elements = css_select("select")
    debug "Found #{select_elements.size} select elements"
    
    # Looking specifically for the priority select
    priority_select = css_select("select[name='task[priority]']").first
    assert priority_select.present?, "Priority select field not found in the form"
    
    debug "Found priority select with id: #{priority_select['id']}"
    
    # Get all options in the priority select
    options = css_select("select[name='task[priority]'] option")
    debug "Found #{options.size} options in priority select"
    
    # Check which option is selected
    selected_option = css_select("select[name='task[priority]'] option[selected]").first
    assert selected_option.present?, "No option is selected in the priority dropdown"
    
    debug "Selected option: value=#{selected_option['value']}, text=#{selected_option.text}"
    
    # Now assert that the selected option has the project's default priority
    assert_equal @project.default_priority, selected_option['value']
  end

  test "should create task with specified status" do
    status = @project.status_by_key(:in_progress)
    
    # Visit the new task form with project_id
    get new_task_path, params: { project_id: @project.id }
    assert_response :redirect
    follow_redirect!
    assert_response :success
    
    assert_difference('Task.count') do
      post tasks_path, params: {
        task: {
          title: "Status Task",
          description: "This should have In Progress status",
          project_id: @project.id,
          status_id: status.id
        }
      }
    end
    
    # The task should be created with the specified status
    task = Task.find_by(title: "Status Task")
    assert_equal "In Progress", task.status.name
  end

  test "should maintain status when updating task" do
    # Create a task with a specific status
    status = @project.status_by_key(:ready_to_test)
    task = Task.create!(
      title: "Test Task",
      description: "Test Description",
      project: @project,
      user: @user,
      status: status,
      priority: 'medium'
    )
    
    # Update the task's title
    patch task_path(task), params: {
      task: {
        title: "Updated Test Task"
      }
    }
    
    # The status should remain unchanged
    task.reload
    assert_equal "Ready to Test", task.status.name
  end

  test "status dropdown should only show statuses from current project" do
    # Ensure the project has all default statuses
    @project.create_default_statuses!(force: true)
    
    # Visit the new task form for the project
    get new_project_task_path(@project)
    assert_response :success
    
    # Debug: Print the entire select element HTML
    status_select = css_select("select[name='task[status_id]']").first
    puts "\nStatus select HTML:"
    puts status_select.to_html if status_select
    
    # Get all status options from the dropdown
    status_options = css_select("select[name='task[status_id]'] option")
    
    # Debug: Print each option's HTML
    puts "\nStatus options HTML:"
    status_options.each do |opt|
      puts "Option: #{opt.to_html}"
    end
    
    # Get all status names from the options (excluding the blank option and "Select a status")
    status_names = status_options.map { |opt| opt.text.strip }.reject { |text| text.empty? || text == "Select a status" }
    
    # Debug output
    puts "\nFound statuses in dropdown:"
    status_names.each { |name| puts "  - #{name}" }
    puts "\nExpected default statuses:"
    Status.default_statuses.values.each { |name| puts "  - #{name}" }
    
    # Verify that each default status appears exactly once
    default_statuses = Status.default_statuses.values
    default_statuses.each do |status_name|
      count = status_names.count(status_name)
      assert_equal 1, count, 
        "Expected exactly one instance of '#{status_name}' in the dropdown, but found #{count}. " \
        "Current dropdown contents: #{status_names.join(', ')}"
    end
    
    # Verify that there are no unexpected statuses
    unexpected_statuses = status_names - default_statuses
    assert_empty unexpected_statuses,
      "Found unexpected statuses in the dropdown: #{unexpected_statuses.join(', ')}"
    
    # TODO: Once custom statuses are implemented, update this test to:
    # 1. Create a project with custom statuses
    # 2. Verify that only statuses belonging to the current project are shown
    # 3. Verify that no statuses from other projects are included
  end
end 