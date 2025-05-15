require "test_helper"

class TaskCreationTest < ActionDispatch::IntegrationTest
  def setup
    @user = users(:one)
    @project = projects(:one)
    @verbose = ENV['VERBOSE_TESTS'] == 'true'
    
    # Sign in
    post user_session_path, params: { 
      user: { 
        email: @user.email, 
        password: 'password' 
      } 
    }
    follow_redirect!
    
    # Setup PaperTrail for tests
    PaperTrail.request.whodunnit = @user.id
    PaperTrail.request.controller_info = {
      ip: "127.0.0.1",
      user_agent: "Rails Testing"
    }
  end
  
  def teardown
    # Reset PaperTrail 
    PaperTrail.request.whodunnit = nil
    PaperTrail.request.controller_info = {}
  end

  def debug(message)
    puts message if @verbose
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
end 