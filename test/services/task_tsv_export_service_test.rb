require "test_helper"
require "csv"

class TaskTsvExportServiceTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @project = projects(:one)
    setup_paper_trail
  end

  teardown do
    teardown_paper_trail
  end

  test "includes a header row" do
    tsv = TaskTsvExportService.call([])
    header_row = tsv.lines.first.chomp.split("\t")

    assert_equal ["Title", "Priority", "Status", "Due Date", "Category", "Description"], header_row
  end

  test "renders each task's core fields as a tab-separated row" do
    task = @project.create_task!(
      title: "Water the plants",
      description: "Twice a week",
      priority: "medium",
      due_date: Date.new(2026, 8, 1),
      user: @user,
      task_category: task_categories(:feature)
    )

    tsv = TaskTsvExportService.call([task])
    rows = CSV.parse(tsv, col_sep: "\t")

    assert_equal ["Water the plants", "medium", "Not Started", "2026-08-01", "Feature", "Twice a week"], rows[1]
  end

  test "blank optional fields render as empty columns" do
    task = @project.create_task!(title: "Bare task", user: @user)

    tsv = TaskTsvExportService.call([task])
    rows = CSV.parse(tsv, col_sep: "\t")

    assert_equal "Bare task", rows[1][0]
    assert_nil rows[1][3], "expected no due date"
    assert_nil rows[1][4], "expected no category"
    assert_nil rows[1][5], "expected no description"
  end

  test "a title or description containing a literal tab or newline is still parsed back correctly" do
    task = @project.create_task!(
      title: "Tricky\ttitle",
      description: "Line one\nLine two",
      user: @user
    )

    tsv = TaskTsvExportService.call([task])
    rows = CSV.parse(tsv, col_sep: "\t")

    assert_equal "Tricky\ttitle", rows[1][0]
    assert_equal "Line one\nLine two", rows[1][5]
  end
end
