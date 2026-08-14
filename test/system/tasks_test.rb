require "application_system_test_case"

class TasksTest < ApplicationSystemTestCase
  def setup
    @user = users(:one)
    @project = projects(:one)
    @task = tasks(:one)
    sign_in_as(@user)
  end

  test "creating a task" do
    # new_task_path (no project_id) redirects to projects_path - the form only
    # renders for the project-scoped route.
    visit new_project_task_path(@project)

    fill_in "task_title", with: "New System Test Task"
    fill_in "task-description", with: "This is a test task created through system tests"
    select @project.title, from: "Project"
    click_on "Save Task"

    assert_text "Task was successfully created"
    assert_text "New System Test Task"
  end

  test "editing a task" do
    visit edit_task_path(@task)

    fill_in "task_title", with: "Updated System Test Task"
    fill_in "task-description", with: "This task has been updated through system tests"
    click_on "Save Task"

    assert_text "Task was successfully updated"
    assert_text "Updated System Test Task"
  end

  test "toggling task completion" do
    # A CSS selector string, not a pre-resolved node: within(a_string) re-runs
    # this query fresh on every internal retry, so it can't go stale the way
    # within(some_element_found_earlier) can when the page mutates (a form
    # submit, a reload) between resolving that element and using it. Scoped
    # via the toggle form's own data-task-title (exact attribute match) rather
    # than @task.title text, since "Test Task" is itself a substring of the
    # fixture task "Another Test Task".
    task_row_selector = ".task-item:has(form[data-task-title='#{@task.title}'])"

    visit tasks_path(show_completed: true)
    within(task_row_selector) { assert_no_selector ".bg-green-500" }
    within(task_row_selector) { find("form[data-task-title='#{@task.title}'] button").click }

    # Marking a task complete (task_result_modal.js) intercepts the toggle
    # form's submit and opens a "task result" modal instead of submitting
    # right away - it only re-submits (with the chosen result attached) once
    # confirmed here. "complete" is already the modal's default selection.
    within("#task-result-modal") { click_on "Save result" }

    # click only dispatches the click event - it doesn't wait for the
    # ensuing (async, from the test process's point of view) request/redirect
    # to finish server-side. @task.reload is a plain DB read with no
    # Capybara-level waiting/retrying of its own, so without first waiting on
    # something Capybara DOES synchronize on, it can run before the server
    # has processed the toggle at all. This flash notice only appears once
    # the redirect_back round trip has completed.
    assert_text "Task status updated."
    assert @task.reload.completed, "expected the task to be marked completed after toggling"

    # Re-visit rather than trust where the toggle's redirect_back lands - only
    # the DB state (checked above) is asserted as a direct effect of the
    # click; this reload deterministically gets back to a view where a
    # completed task is still visible, to check its rendered state.
    visit tasks_path(show_completed: true)
    within(task_row_selector) { assert_selector ".bg-green-500" }
  end

  test "archiving a task" do
    visit tasks_path
    row = find_link(@task.title, exact: true).ancestor(".task-item")

    accept_confirm do
      within(row) { find("button[data-confirm]").click }
    end

    assert_text "Task was successfully archived"
    assert_no_link @task.title, exact: true
  end

  test "deleting a task shows a modal with the task title and a comments warning, then deletes it" do
    visit tasks_path

    row = find_link(@task.title, exact: true).ancestor(".task-item")
    within(row) { find("button[title='#{I18n.t('views.tasks.index.delete_task')}']").click }

    within("[data-delete-task-confirm-target='modal']") do
      assert_text I18n.t('views.tasks.index.delete_confirm.title')
      assert_text @task.title
      assert_text I18n.t('views.tasks.index.delete_confirm.comments_warning', count: @task.comments.size)
      click_on I18n.t('views.tasks.index.delete_confirm.confirm')
    end

    assert_text I18n.t('views.tasks.index.deleted')
    assert_no_link @task.title, exact: true
  end

  test "canceling the delete modal leaves the task in place" do
    visit tasks_path

    row = find_link(@task.title, exact: true).ancestor(".task-item")
    within(row) { find("button[title='#{I18n.t('views.tasks.index.delete_task')}']").click }

    within("[data-delete-task-confirm-target='modal']") do
      click_on I18n.t('views.tasks.index.delete_confirm.cancel')
    end

    assert_text @task.title
  end

  test "deleting a task without comments hides the comments warning" do
    task_without_comments = tasks(:reprioritize_high)
    visit tasks_path

    row = find_link(task_without_comments.title, exact: true).ancestor(".task-item")
    within(row) { find("button[title='#{I18n.t('views.tasks.index.delete_task')}']").click }

    within("[data-delete-task-confirm-target='modal']") do
      assert_no_selector("[data-delete-task-confirm-target='commentsWarning']")
    end
  end

  test "adding a comment to a task" do
    visit task_path(@task)
    
    fill_in "comment_content", with: "This is a test comment"
    click_on "Post Comment"

    assert_text "This is a test comment"
    assert_text @user.name
  end
end 