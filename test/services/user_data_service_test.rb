require "test_helper"

class UserDataServiceTest < ActiveSupport::TestCase
  def setup
    @user = users(:one)
    @project = projects(:one)
    setup_paper_trail
  end

  def teardown
    teardown_paper_trail
  end

  test "importing a task with a title similar to an existing sibling task does not fail" do
    # Mirrors what a recurring task template generates: the same base title
    # with only a date label changing between instances - RecurringTaskTemplate
    # bypasses the similar-title check for exactly this reason (see
    # RecurringTaskTemplate#generate_task_for_period!).
    @project.tasks.create!(user: @user, title: "Water plants (2026-01)", skip_duplicate_check: true)

    data = {
      "export_info" => { "version" => "1.0" },
      "user" => { "id" => @user.id },
      "tags" => [],
      "projects" => [
        {
          "name" => @project.title,
          "description" => @project.description,
          "priority" => @project.default_priority,
          "created_at" => @project.created_at,
          "updated_at" => @project.updated_at,
          "statuses" => [],
          "tasks" => [
            {
              "title" => "Water plants (2026-02)",
              "description" => "",
              "priority" => "medium",
              "comments" => [
                { "content" => "Looks a bit wilted", "status" => "open", "created_at" => Time.current, "updated_at" => Time.current }
              ]
            }
          ],
          "comments" => []
        }
      ]
    }

    result = UserDataService.import_data(@user, json_file(data), password: nil)

    assert result[:success], "Expected import to succeed, got error: #{result[:error]}"
    assert @project.tasks.exists?(title: "Water plants (2026-01)")
    imported_task = @project.tasks.find_by(title: "Water plants (2026-02)")
    assert imported_task
    assert_equal @user, imported_task.user
    assert_equal "Looks a bit wilted", imported_task.comments.sole.content
    assert_equal @user, imported_task.comments.sole.user
  end

  test "importing a project with a title similar to an existing project does not fail" do
    @user.projects.create!(title: "Kitchen Remodel Phase 1")

    data = {
      "export_info" => { "version" => "1.0" },
      "user" => { "id" => @user.id },
      "tags" => [],
      "projects" => [
        {
          "name" => "Kitchen Remodel Phase 2",
          "description" => "",
          "priority" => "medium",
          "statuses" => [],
          "tasks" => [],
          "comments" => []
        }
      ]
    }

    result = UserDataService.import_data(@user, json_file(data), password: nil)

    assert result[:success], "Expected import to succeed, got error: #{result[:error]}"
    assert @user.projects.exists?(title: "Kitchen Remodel Phase 1")
    assert @user.projects.exists?(title: "Kitchen Remodel Phase 2")
  end

  private

  def json_file(data)
    file = StringIO.new(data.to_json)
    file.define_singleton_method(:original_filename) { "export.json" }
    file
  end
end
