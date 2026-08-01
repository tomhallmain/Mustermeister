require "application_system_test_case"

class TaskMergeTest < ApplicationSystemTestCase
  def setup
    @user = users(:one)
    @project = projects(:one)
    setup_paper_trail(@user)
    sign_in_as(@user)
  end

  def teardown
    teardown_paper_trail
  end

  test "merging two tasks from the tasks index keeps the longer title and removes the other task" do
    target = @project.tasks.create!(title: "Short", user: @user, skip_duplicate_check: true)
    source = @project.tasks.create!(title: "A much longer title", user: @user, skip_duplicate_check: true)

    visit tasks_path
    click_on I18n.t('views.tasks.merge.entry_link')

    select "#{target.title} (#{@project.title})", from: I18n.t('views.tasks.merge.keep_label')
    select "#{source.title} (#{@project.title})", from: I18n.t('views.tasks.merge.merge_away_label')

    accept_confirm do
      click_on I18n.t('views.tasks.merge.confirm_button')
    end

    assert_text I18n.t('views.tasks.merge.success', target_title: source.title)
    assert_text source.title
    assert_no_text target.title
  end
end
