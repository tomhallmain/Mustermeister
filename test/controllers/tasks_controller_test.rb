require "test_helper"

class TasksControllerTest < ActionDispatch::IntegrationTest
  def setup
    # Dynamically override the layout for TasksController
    TasksController.class_eval do
      layout 'test'
    end
    
    @user = users(:one)
    @project = projects(:one)
    @task = tasks(:one)
    @project.create_default_statuses!  # Ensure default statuses are created
    sign_in_as(@user, skip_redirect: true)
    
    setup_paper_trail
  end

  def teardown
    # Reset to default layout
    TasksController.class_eval do
      layout 'application'
    end
    
    teardown_paper_trail
  end

  test "should get index" do
    # The index action now redirects to add show_completed param if missing
    get tasks_path(show_completed: false)
    assert_response :success
    assert_select "h1", "Tasks"
  end

  test "tasks index displays a task's category badge" do
    @task.update!(task_category: task_categories(:feature))

    get tasks_path(show_completed: false)
    assert_response :success

    assert_match "Feature", response.body
  end

  test "tasks index task row includes a quick-copy link" do
    get tasks_path(show_completed: false)
    assert_response :success

    assert_select "a[href=?]", new_project_task_path(@task.project, source_task_id: @task.id, show_completed: 'false')
  end

  test "tasks index shows a duplicate last task button pointing at the most recently created task" do
    # Relative to @task (tasks(:one), created_at: Time.current from fixtures) rather than
    # to "now" directly, since @task is otherwise the most recently created task in play here.
    @project.create_task!(title: "Older Task", user: @user, created_at: @task.created_at - 2.days)
    newer_task = @project.create_task!(title: "Newer Task", user: @user, created_at: @task.created_at + 1.hour)

    get tasks_path(show_completed: false)
    assert_response :success

    # Every row also has its own quick-copy link, so this must be scoped to the
    # header button specifically (identified by its text) rather than just
    # asserting on the href, which legitimately appears once per row too.
    assert_select "a[href=?]", new_project_task_path(newer_task.project, source_task_id: newer_task.id, show_completed: 'false'),
      text: /Duplicate Last Task/
  end

  test "tasks index does not show a duplicate last task button when the user has no tasks" do
    # Reassign rather than switching signed-in users mid-test: signing in a
    # second time within one test flips Devise's response format to HTML
    # (see Users::SessionsController#set_request_format) and redirects instead
    # of the JSON response sign_in_as expects.
    @user.tasks.update_all(user_id: users(:two).id)

    get tasks_path(show_completed: false)
    assert_response :success

    assert_select "a", text: /Duplicate Last Task/, count: 0
  end

  test "should redirect to tasks when trying to create task without project" do
    get new_task_path
    assert_redirected_to tasks_path(show_completed: false)
  end

  test "should create task with default status" do
    assert_difference('Task.count') do
      post tasks_path, params: {
        task: {
          title: "New Task",
          description: "Task Description",
          project_id: @project.id
        }
      }
    end

    task = Task.last
    assert_equal "Not Started", task.status.name
    assert_redirected_to project_path(task.project, show_completed: false)
  end

  test "should create task with specified status" do
    status = @project.status_by_key(:in_progress)
    assert_difference('Task.count') do
      post tasks_path, params: {
        task: {
          title: "New Task",
          description: "Task Description",
          project_id: @project.id,
          status_id: status.id
        }
      }
    end

    task = Task.last
    assert_equal "In Progress", task.status.name
    assert_redirected_to project_path(task.project, show_completed: false)
  end

  test "should use specified priority when creating task" do
    # Set a default priority on the project
    @project.update!(default_priority: 'high')
    
    # Create the task with explicit low priority
    assert_difference('Task.count') do
      post tasks_path, params: {
        task: {
          title: "Low Priority Task",
          description: "This should use explicit low priority",
          project_id: @project.id,
          priority: 'low'
        }
      }
    end
    
    # Verify the task got the explicit priority, not project default
    task = Task.find_by(title: "Low Priority Task")
    assert_equal 'low', task.priority
  end

  test "should show task" do
    get task_path(@task)
    assert_response :success
  end

  test "task show includes a link to duplicate the task" do
    get task_path(@task)
    assert_response :success

    assert_select "a[href=?]", new_project_task_path(@task.project, source_task_id: @task.id)
  end

  test "task show displays the task's category badge" do
    @task.update!(task_category: task_categories(:feature))

    get task_path(@task)
    assert_response :success

    assert_select "h3", text: "Category"
    assert_match "Feature", response.body
  end

  test "task show omits the category block when the task has no category" do
    @task.update!(task_category: nil)

    get task_path(@task)
    assert_response :success

    assert_select "h3", text: "Category", count: 0
  end

  test "task show displays status change history" do
    new_status = @project.status_by_key(:in_progress)
    assert_not_nil new_status

    patch task_path(@task), params: { task: { status_id: new_status.id } }

    get task_path(@task)

    assert_response :success
    assert_select "h2", text: "Status History"
    assert_match(/In Progress/, response.body)
    assert_match(@user.name, response.body)
  end

  test "task show renders markdown in comments" do
    task = tasks(:markdown_test_task)

    get task_path(task)

    assert_response :success
    assert_select "strong", text: "Insight from review"
    assert_select "code", text: "inline comment code"
  end

  test "kanban_tasks should include project color in JSON response" do
    # Ensure project has a color set
    @project.update!(color: 'green')
    
    # Debug: Check if the project actually has the color set
    @project.reload
    assert_equal 'green', @project.color, "Project color should be 'green'"
    
    get kanban_tasks_path, as: :json
    assert_response :success
    
    json_response = JSON.parse(response.body)
    assert_includes json_response.keys, 'tasks'
    
    # Check that tasks include project_color
    # Only check tasks that belong to our updated project
    json_response['tasks'].each do |status, tasks|
      tasks.each do |task|
        assert_includes task.keys, 'project_color'
        # Only assert the color for tasks from our specific project
        if task['project'] == @project.title
          assert_equal 'green', task['project_color'], "Expected project_color to be 'green' for project '#{@project.title}', got '#{task['project_color']}'"
        end
      end
    end
  end

  test "kanban_tasks should include the task's category display name in JSON response" do
    @task.update!(task_category: task_categories(:feature))

    get kanban_tasks_path, as: :json
    assert_response :success

    json_response = JSON.parse(response.body)
    categorized_task = json_response['tasks'].values.flatten.find { |task| task['id'] == @task.id }

    assert_not_nil categorized_task, "Expected the updated task to appear in the kanban JSON response"
    assert_equal 'Feature', categorized_task['category']
  end

  test "kanban_tasks should return a nil category for tasks without one" do
    @task.update!(task_category: nil)

    get kanban_tasks_path, as: :json
    assert_response :success

    json_response = JSON.parse(response.body)
    task = json_response['tasks'].values.flatten.find { |t| t['id'] == @task.id }

    assert_not_nil task
    assert_nil task['category']
  end

  # Kanban UI: dragging to Complete opens the result modal; cancel skips PATCH. The board then
  # calls GET /kanban/tasks (loadTasks) to repaint from server state — this response must still
  # list the task under its prior status column when no update was persisted.
  test "kanban_tasks lists task in prior status bucket when completion was not saved (e.g. modal cancel)" do
    task = @project.tasks.create!(
      title: "Kanban cancel refresh scenario",
      description: "Server status unchanged if PATCH not sent",
      user: @user,
      status: @project.status_by_key(:in_progress)
    )

    get kanban_tasks_path, as: :json
    assert_response :success

    json_response = JSON.parse(response.body)
    in_progress_ids = (json_response["tasks"]["in_progress"] || []).map { |t| t["id"] }
    complete_ids = (json_response["tasks"]["complete"] || []).map { |t| t["id"] }

    assert_includes in_progress_ids, task.id
    assert_not_includes complete_ids, task.id
  end

  test "kanban_tasks should filter by updated_within_days (positive values)" do
    # Create tasks with different updated_at timestamps
    base_time = Time.current
    
    recent_task = @project.tasks.create!(
      title: "Recent Task",
      description: "Updated recently",
      user: @user,
      updated_at: base_time - 2.days,
      status: @project.status_by_key(:not_started)
    )
    
    old_task = @project.tasks.create!(
      title: "Old Task",
      description: "Updated long ago",
      user: @user,
      updated_at: base_time - 10.days,
      status: @project.status_by_key(:not_started)
    )
    
    # Test filter for tasks updated within 7 days (should include recent_task, exclude old_task)
    get kanban_tasks_path(updated_within_days: 7), as: :json
    assert_response :success
    
    json_response = JSON.parse(response.body)
    all_tasks = json_response['tasks'].values.flatten
    
    recent_task_found = all_tasks.any? { |t| t['id'] == recent_task.id }
    old_task_found = all_tasks.any? { |t| t['id'] == old_task.id }
    
    assert recent_task_found, "Recent task should be included when filtering for last 7 days"
    assert_not old_task_found, "Old task should be excluded when filtering for last 7 days"
  end

  test "kanban_tasks should filter by updated_within_days (negative values)" do
    # Create tasks with different updated_at timestamps
    base_time = Time.current
    
    recent_task = @project.tasks.create!(
      title: "Recent Task",
      description: "Updated recently",
      user: @user,
      updated_at: base_time - 2.days,
      status: @project.status_by_key(:not_started)
    )
    
    old_task = @project.tasks.create!(
      title: "Old Task",
      description: "Updated long ago",
      user: @user,
      updated_at: base_time - 10.days,
      status: @project.status_by_key(:not_started)
    )
    
    # Test filter for tasks NOT updated within 7 days (should exclude recent_task, include old_task)
    get kanban_tasks_path(updated_within_days: -7), as: :json
    assert_response :success
    
    json_response = JSON.parse(response.body)
    all_tasks = json_response['tasks'].values.flatten
    
    recent_task_found = all_tasks.any? { |t| t['id'] == recent_task.id }
    old_task_found = all_tasks.any? { |t| t['id'] == old_task.id }
    
    assert_not recent_task_found, "Recent task should be excluded when filtering for not updated in 7 days"
    assert old_task_found, "Old task should be included when filtering for not updated in 7 days"
  end

  test "kanban_tasks should not filter when updated_within_days is not provided" do
    # Create tasks with different updated_at timestamps
    base_time = Time.current
    
    recent_task = @project.tasks.create!(
      title: "Recent Task",
      description: "Updated recently",
      user: @user,
      updated_at: base_time - 2.days,
      status: @project.status_by_key(:not_started)
    )
    
    old_task = @project.tasks.create!(
      title: "Old Task",
      description: "Updated long ago",
      user: @user,
      updated_at: base_time - 10.days,
      status: @project.status_by_key(:not_started)
    )
    
    # Test without filter (should include both tasks)
    get kanban_tasks_path, as: :json
    assert_response :success
    
    json_response = JSON.parse(response.body)
    all_tasks = json_response['tasks'].values.flatten
    
    recent_task_found = all_tasks.any? { |t| t['id'] == recent_task.id }
    old_task_found = all_tasks.any? { |t| t['id'] == old_task.id }
    
    assert recent_task_found, "Recent task should be included when no filter is applied"
    assert old_task_found, "Old task should be included when no filter is applied"
  end

  test "should get the kanban board page" do
    get kanban_path
    assert_response :success
    assert_select "select#project-filter"
    assert_select "select#priority-filter"
    assert_select "select#sort-by"
    assert_select "select#sort-by option[value='updated_at_asc']"
  end

  # Regression guard for a bug where dropping a card into a short or empty
  # column silently failed whenever a sibling column was much taller (e.g. a
  # large backlog): #kanban-board is a flex row, so every .kanban-column
  # stretches to match the tallest sibling by default, but .kanban-tasks
  # never grew to fill that stretched height - leaving a region that was
  # visually inside the column but outside any Sortable-managed list, so no
  # drag-and-drop configuration could ever make it droppable. The fix makes
  # .kanban-column a flex column and .kanban-tasks flex-1 so it always fills
  # the column's full (stretched) height.
  #
  # This only asserts the markup carries the classes the fix depends on -
  # it can't verify the resulting layout/geometry or an actual drag
  # gesture, since Capybara here runs on the :rack_test driver (see
  # test/test_helper.rb), which does no CSS layout and executes no
  # JavaScript. Confirming this class of bug (and SortableJS drag-and-drop
  # behavior generally) end-to-end would need a JS-capable Capybara driver
  # (e.g. selenium-webdriver, already in the Gemfile but not wired up as
  # Capybara.javascript_driver) driving a real headless browser.
  test "kanban columns stretch their task list to fill the full column height" do
    get kanban_path
    assert_response :success

    assert_select ".kanban-column.flex.flex-col"
    assert_select ".kanban-column .kanban-tasks.flex-1"
  end

  test "kanban board json format returns projects and statuses" do
    get kanban_path, as: :json
    assert_response :success

    json_response = JSON.parse(response.body)
    assert_includes json_response.keys, 'projects'
    assert_includes json_response.keys, 'statuses'
    assert_includes json_response['projects'].map { |p| p['id'] }, @project.id
  end

  test "kanban_tasks sorts by updated_at descending by default" do
    older = @project.tasks.create!(title: "Older Update", user: @user, status: @project.status_by_key(:not_started), updated_at: 2.days.ago)
    newer = @project.tasks.create!(title: "Newer Update", user: @user, status: @project.status_by_key(:not_started), updated_at: 1.hour.ago)

    get kanban_tasks_path, as: :json
    assert_response :success

    ids = JSON.parse(response.body)['tasks']['not_started'].map { |t| t['id'] }
    assert_operator ids.index(newer.id), :<, ids.index(older.id)
  end

  test "kanban_tasks sorts by created_at when requested" do
    older = @project.tasks.create!(title: "Older Created", user: @user, status: @project.status_by_key(:not_started), created_at: 2.days.ago)
    newer = @project.tasks.create!(title: "Newer Created", user: @user, status: @project.status_by_key(:not_started), created_at: 1.hour.ago)

    get kanban_tasks_path(sort_by: 'created_at'), as: :json
    assert_response :success

    ids = JSON.parse(response.body)['tasks']['not_started'].map { |t| t['id'] }
    assert_operator ids.index(newer.id), :<, ids.index(older.id)
  end

  test "kanban_tasks sorts by updated_at ascending when sort_by=updated_at_asc" do
    older = @project.tasks.create!(title: "Older Update", user: @user, status: @project.status_by_key(:not_started), updated_at: 2.days.ago)
    newer = @project.tasks.create!(title: "Newer Update", user: @user, status: @project.status_by_key(:not_started), updated_at: 1.hour.ago)

    get kanban_tasks_path(sort_by: 'updated_at_asc'), as: :json
    assert_response :success

    ids = JSON.parse(response.body)['tasks']['not_started'].map { |t| t['id'] }
    assert_operator ids.index(older.id), :<, ids.index(newer.id)
  end

  test "kanban_tasks sorts by priority using severity rank, not alphabetically" do
    not_started = @project.status_by_key(:not_started)
    high = @project.tasks.create!(title: "High Prio", user: @user, status: not_started, priority: 'high')
    medium = @project.tasks.create!(title: "Medium Prio", user: @user, status: not_started, priority: 'medium')
    low = @project.tasks.create!(title: "Low Prio", user: @user, status: not_started, priority: 'low')
    leisure = @project.tasks.create!(title: "Leisure Prio", user: @user, status: not_started, priority: 'leisure')

    get kanban_tasks_path(sort_by: 'priority'), as: :json
    assert_response :success

    ids = JSON.parse(response.body)['tasks']['not_started'].map { |t| t['id'] }
    relevant_ids = ids & [high.id, medium.id, low.id, leisure.id]
    assert_equal [high.id, medium.id, low.id, leisure.id], relevant_ids
  end

  test "kanban_tasks filters by priority" do
    not_started = @project.status_by_key(:not_started)
    high_task = @project.tasks.create!(title: "High Prio Task", user: @user, status: not_started, priority: 'high')
    low_task = @project.tasks.create!(title: "Low Prio Task", user: @user, status: not_started, priority: 'low')

    get kanban_tasks_path(priority: 'high'), as: :json
    assert_response :success

    ids = JSON.parse(response.body)['tasks'].values.flatten.map { |t| t['id'] }
    assert_includes ids, high_task.id
    assert_not_includes ids, low_task.id
  end

  test "kanban_tasks filters by project_id" do
    other_project = @user.projects.create!(title: "Second Project")
    matching_task = @project.tasks.create!(title: "In Filtered Project", user: @user, status: @project.status_by_key(:not_started))
    other_task = other_project.tasks.create!(title: "In Other Project", user: @user, status: other_project.status_by_key(:not_started))

    get kanban_tasks_path(project_id: @project.id), as: :json
    assert_response :success

    ids = JSON.parse(response.body)['tasks'].values.flatten.map { |t| t['id'] }
    assert_includes ids, matching_task.id
    assert_not_includes ids, other_task.id
  end

  test "kanban_tasks returns not found for a project_id belonging to another user" do
    other_user = users(:two)
    foreign_project = Project.create!(title: "Not Mine", user: other_user)

    get kanban_tasks_path(project_id: foreign_project.id), as: :json
    assert_response :not_found
  end

  test "kanban_tasks show_all_completed defaults to only the last 7 days of completed tasks" do
    complete_status = @project.status_by_key(:complete)
    old_completed = @project.tasks.create!(title: "Old Completed", user: @user, status: complete_status)
    old_completed.update_column(:updated_at, 10.days.ago)

    get kanban_tasks_path, as: :json
    assert_response :success

    ids = JSON.parse(response.body)['tasks']['complete'].map { |t| t['id'] }
    assert_not_includes ids, old_completed.id
  end

  test "kanban_tasks show_all_completed=true includes older completed tasks" do
    complete_status = @project.status_by_key(:complete)
    old_completed = @project.tasks.create!(title: "Old Completed", user: @user, status: complete_status)
    old_completed.update_column(:updated_at, 10.days.ago)

    get kanban_tasks_path(show_all_completed: 'true'), as: :json
    assert_response :success

    ids = JSON.parse(response.body)['tasks']['complete'].map { |t| t['id'] }
    assert_includes ids, old_completed.id
  end

  test "kanban_tasks paginates within a status bucket and reports has_more" do
    not_started = @project.status_by_key(:not_started)
    101.times { |i| @project.tasks.create!(title: "Bulk Task #{i}", user: @user, status: not_started) }
    total = @user.tasks.not_archived.joins(:status).where(statuses: { name: 'Not Started' }).count

    get kanban_tasks_path, as: :json
    assert_response :success
    page_one = JSON.parse(response.body)

    assert_equal [total, 100].min, page_one['tasks']['not_started'].size
    assert_equal total > 100, page_one['has_more']

    get kanban_tasks_path(page: 2), as: :json
    assert_response :success
    page_two = JSON.parse(response.body)

    assert_equal [total - 100, 0].max, page_two['tasks']['not_started'].size
    page_one_ids = page_one['tasks']['not_started'].map { |t| t['id'] }
    page_two_ids = page_two['tasks']['not_started'].map { |t| t['id'] }
    assert_empty page_one_ids & page_two_ids, "Page 2 should not repeat tasks already shown on page 1"
  end

  test "kanban task update should redirect to login when session expired" do
    # Simulate an expired session by manipulating the session cookie expiration
    # The session store is configured with expire_after: 1.hours
    travel_to 2.hours.from_now do
      patch task_path(@task, kanban: true), params: {
        task: {
          status_name: 'In Progress'
        }
      }, as: :json
      
      # Devise redirects to login page when session expires, even for JSON requests
      # For JSON requests, the redirect URL includes .json extension
      assert_response :redirect
      assert_redirected_to new_user_session_path(format: :json)
    end
  end

  test "should get edit" do
    get edit_task_path(@task)
    assert_response :success
  end

  test "should update task" do
    patch task_path(@task), params: {
      task: {
        title: "Updated Task",
        description: "Updated Description"
      }
    }
    assert_redirected_to project_path(@task.project, show_completed: false)
    @task.reload
    assert_equal "Updated Task", @task.title
  end

  test "should update task with new status" do
    new_status = @project.status_by_key(:ready_to_test)
    assert_not_nil new_status, "Ready to Test status should exist"
    
    patch task_path(@task), params: {
      task: {
        status_id: new_status.id
      }
    }
    assert_redirected_to project_path(@task.project, show_completed: false)
    @task.reload
    assert_equal "Ready to Test", @task.status.name
  end

  test "switching a task's project via update remaps a stale status from the old project" do
    @task.update!(status: @project.status_by_key(:in_progress))
    other_project = projects(:two)
    other_project.create_default_statuses!
    stale_status_id = @task.status_id # still belongs to @project, the old one

    patch task_path(@task), params: {
      task: {
        project_id: other_project.id,
        status_id: stale_status_id
      }
    }

    assert_response :redirect
    @task.reload
    assert_equal other_project, @task.project
    assert_equal other_project, @task.status.project
    assert_equal "In Progress", @task.status.name
  end

  test "should maintain status when updating other fields" do
    original_status = @task.status
    patch task_path(@task), params: {
      task: {
        title: "Updated Title",
        description: "Updated Description"
      }
    }
    assert_redirected_to project_path(@task.project, show_completed: false)
    @task.reload
    assert_equal original_status, @task.status
  end

  test "should handle invalid status id gracefully" do
    original_status = @task.status
    
    patch task_path(@task), params: {
      task: {
        status_id: 999999  # Non-existent status ID
      }
    }
    
    # Should redirect back to the project page
    assert_redirected_to project_path(@task.project, show_completed: false)
    
    # Status should remain unchanged
    @task.reload
    assert_equal original_status, @task.status
  end

  test "should destroy task" do
    assert_difference('Task.count', -1) do
      delete task_path(@task)
    end

    assert_redirected_to project_path(@task.project, show_completed: false)
  end

  test "should toggle task completion" do
    patch toggle_task_path(@task)
    assert_redirected_to tasks_path(show_completed: false)
    @task.reload
    assert @task.completed
    assert_equal "Complete", @task.status.name
    assert_equal "complete", @task.task_result.result
  end

  test "should save incomplete result and reason when toggling task completion" do
    patch toggle_task_path(@task), params: {
      task_result: {
        result: "incomplete",
        result_reason: "Too Challenging"
      }
    }

    assert_redirected_to tasks_path(show_completed: false)
    @task.reload
    assert @task.completed
    assert_equal "incomplete", @task.task_result.result
    assert_equal "Too Challenging", @task.task_result.result_reason
  end

  test "should reject incomplete result without reason when toggling task completion" do
    patch toggle_task_path(@task), params: {
      task_result: {
        result: "incomplete",
        result_reason: ""
      }
    }

    assert_redirected_to tasks_path(show_completed: false)
    @task.reload
    assert_not @task.completed
  end

  test "should archive task" do
    post archive_task_path(@task)
    assert_redirected_to tasks_path(show_completed: false)
    @task.reload
    assert @task.archived
  end

  test "should refresh task and update updated_at timestamp" do
    # Set an old updated_at timestamp
    old_updated_at = 1.day.ago
    @task.update_column(:updated_at, old_updated_at)
    @task.reload
    assert_equal old_updated_at.to_i, @task.updated_at.to_i
    
    # Call refresh action
    patch refresh_task_path(@task)
    
    # Verify redirect
    assert_redirected_to task_path(@task)
    
    # Verify updated_at is now more recent than the old timestamp
    @task.reload
    assert @task.updated_at > old_updated_at
    assert @task.updated_at <= Time.current
  end

  test "should search tasks by title and description" do
    # Search for "zeb" which should match our search test fixtures
    get tasks_path(search: "zeb", show_completed: false)
    assert_response :success
    
    # Verify all search results are present
    assert_select ".task-item", 4
    assert_select ".task-item", text: /Zebra Task/
    assert_select ".task-item", text: /My Zebra/
    assert_select ".task-item", text: /The Amazing Task/
    assert_select ".task-item", text: /The Great Task/
  end

  test "should combine search with show_completed filter" do
    # Mark one of the search tasks as completed
    tasks(:search_test_one).update!(completed: true)
    
    # Search with completed tasks hidden
    get tasks_path(search: "zeb", show_completed: false)
    assert_response :success
    assert_select ".task-item", 3
    
    # Search with completed tasks shown
    get tasks_path(search: "zeb", show_completed: true)
    assert_response :success
    assert_select ".task-item", 5
  end

  test "should set status to complete when creating task with completed checkbox" do
    assert_difference('Task.count') do
      post tasks_path, params: {
        task: {
          title: "Completed Task",
          description: "This task is completed",
          project_id: @project.id,
          completed: true
        }
      }
    end

    task = Task.last
    assert_equal Status.find_by(name: Status.default_statuses[:complete]), task.status
    assert task.completed?
    assert task.complete?
  end

  test "task result modal markup includes context hooks and localized heading" do
    with_tasks_application_layout do
      get tasks_path(show_completed: false)
      assert_response :success
      assert_select "#task-result-modal"
      assert_select "#task-result-modal #task-result-modal-context.hidden"
      assert_select "#task-result-modal #task-result-modal-task-title"
      assert_select "#task-result-modal #task-result-modal-project-name"
      assert_select "#task-result-modal h2", I18n.t("views.tasks.result_modal.title")
    end
  end

  test "tasks index toggle forms include accurate task title and project for result modal context" do
    with_tasks_application_layout do
      get tasks_path(show_completed: false)
      assert_response :success
      # Index passes params[:show_completed] into toggle_task_path (string "false" from query), so action includes ?show_completed=
      assert_select "form[action^='/tasks/#{@task.id}/toggle'][data-task-title='#{@task.title}'][data-project-name='#{@project.title}']"
    end
  end

  test "task show toggle form includes accurate task title and project for result modal context" do
    with_tasks_application_layout do
      get task_path(@task)
      assert_response :success
      assert_select "form[action='#{toggle_task_path(@task)}'][data-task-title='#{@task.title}'][data-project-name='#{@project.title}']"
    end
  end

  test "kanban_tasks JSON includes title and project for each task (modal context on board)" do
    get kanban_tasks_path, as: :json
    assert_response :success
    json = JSON.parse(response.body)
    flat = json["tasks"].values.flatten
    assert flat.any?

    flat.each do |task|
      assert task.key?("title"), "expected title key"
      assert task.key?("project"), "expected project key"
      assert_instance_of String, task["title"]
      assert_instance_of String, task["project"]
    end
  end

  private

  def with_tasks_application_layout
    TasksController.class_eval { layout "application" }
    yield
  ensure
    TasksController.class_eval { layout "test" }
  end
end 