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

    assert_equal ["Title", "Status", "Priority", "Category", "Due Date", "Created", "Updated", "Description"],
                 header_row
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

    assert_equal ["Water the plants", "Not Started", "medium", "Feature", "2026-08-01",
                  task.created_at.to_date.iso8601, task.updated_at.to_date.iso8601, "Twice a week"],
                 rows[1]
  end

  test "blank optional fields render as empty columns" do
    task = @project.create_task!(title: "Bare task", user: @user)

    tsv = TaskTsvExportService.call([task])
    rows = CSV.parse(tsv, col_sep: "\t")

    assert_equal "Bare task", rows[1][0]
    assert_equal "Feature", rows[1][3], "expected the global default category"
    assert_nil rows[1][4], "expected no due date"
    assert_nil rows[1][7], "expected no description"
  end

  test "a task with its category explicitly cleared renders an empty category column" do
    task = @project.create_task!(title: "Bare task", user: @user)
    task.update!(task_category: nil)

    tsv = TaskTsvExportService.call([task])
    rows = CSV.parse(tsv, col_sep: "\t")

    assert_nil rows[1][3], "expected no category"
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
    assert_equal "Line one\nLine two", rows[1][7]
  end

  test "created and updated dates round-trip as ISO 8601 dates" do
    task = @project.create_task!(title: "Dated task", user: @user)
    task.update!(created_at: Time.utc(2026, 3, 1, 9), updated_at: Time.utc(2026, 4, 2, 17))

    rows = CSV.parse(TaskTsvExportService.call([task]), col_sep: "\t")

    assert_equal "2026-03-01", rows[1][5]
    assert_equal "2026-04-02", rows[1][6]
  end
end
