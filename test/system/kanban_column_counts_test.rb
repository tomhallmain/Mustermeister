require "application_system_test_case"

class KanbanColumnCountsTest < ApplicationSystemTestCase
  def setup
    @user = users(:one)
    @project = projects(:one)
    @project.create_default_statuses!
    setup_paper_trail(@user)
    sign_in_as(@user)
  end

  def teardown
    teardown_paper_trail
  end

  test "column headers show how many cards are currently in each column" do
    visit kanban_path

    assert_selector ".kanban-column[data-status='not_started'] [data-task-id]"

    visible = page.all(".kanban-column[data-status='not_started'] .kanban-tasks [data-task-id]").size
    assert_selector ".kanban-column[data-status='not_started'] [data-kanban-column-count]",
                    text: "(#{visible})"
  end
end
