require "application_system_test_case"

class TasksTest < ApplicationSystemTestCase
  def setup
    @user = users(:one)
    @project = projects(:one)
    @task = tasks(:one)
    sign_in_as(@user)
  end

  test "creating a task" do
    visit new_task_path

    fill_in "Title", with: "New System Test Task"
    fill_in "Description", with: "This is a test task created through system tests"
    select @project.title, from: "Project"
    click_on "Create Task"

    assert_text "Task was successfully created"
    assert_text "New System Test Task"
  end

  test "editing a task" do
    visit edit_task_path(@task)

    fill_in "Title", with: "Updated System Test Task"
    fill_in "Description", with: "This task has been updated through system tests"
    click_on "Update Task"

    assert_text "Task was successfully updated"
    assert_text "Updated System Test Task"
  end

  test "toggling task completion" do
    visit tasks_path
    assert_no_selector ".bg-green-500"

    find("button[data-method='patch']").click
    assert_selector ".bg-green-500"
  end

  test "archiving a task" do
    visit task_path(@task)
    
    accept_confirm do
      click_on "Archive"
    end

    assert_text "Task was successfully archived"
    visit tasks_path
    assert_no_text @task.title
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
    assert_no_text @task.title
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