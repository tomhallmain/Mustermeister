require "application_system_test_case"

class ProjectMergeTest < ApplicationSystemTestCase
  def setup
    @user = users(:one)
    @project = projects(:one)
    sign_in_as(@user)
  end

  test "merging two projects moves tasks into the target and deletes the source" do
    target = @user.projects.create!(title: "Target Project")
    task = @project.tasks.create!(title: "Task to move", user: @user)

    visit merge_project_path(@project)
    select target.title, from: I18n.t('views.projects.merge.target_label')
    click_on I18n.t('views.projects.merge.continue')

    accept_confirm do
      click_on I18n.t('views.projects.merge.confirm_button')
    end

    assert_text I18n.t('views.projects.merge.success', source_title: @project.title, target_title: target.title)

    visit project_path(target)
    assert_text task.title
  end
end
