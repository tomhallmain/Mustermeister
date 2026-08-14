require "application_system_test_case"

class ProjectTaskDeleteTest < ApplicationSystemTestCase
  def setup
    @user = users(:one)
    @project = projects(:one)
    @task = tasks(:one)
    sign_in_as(@user)
  end

  test "deleting a task from the project page shows the modal (not a native alert), then deletes it" do
    visit project_path(@project)

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

  test "canceling the delete modal on the project page leaves the task in place" do
    visit project_path(@project)

    row = find_link(@task.title, exact: true).ancestor(".task-item")
    within(row) { find("button[title='#{I18n.t('views.tasks.index.delete_task')}']").click }

    within("[data-delete-task-confirm-target='modal']") do
      click_on I18n.t('views.tasks.index.delete_confirm.cancel')
    end

    assert_text @task.title
  end
end
