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

  test "importing a TSV file bulk-creates tasks grouped by project" do
    tsv = <<~TSV
      Title\tPriority\tStatus\tProject\tDescription
      Fix mktemp templates\tmedium\tReady to Test\tCode - dev_scripts\tBump to 6+ X's for BusyBox.
      Add ngram command\tmedium\tNot Started\tCode - dev_scripts\tNo ngram command exists yet.
    TSV

    result = UserDataService.import_data(@user, tsv_file(tsv), password: nil)

    assert result[:success], "Expected import to succeed, got error: #{result[:error]}"
    assert_equal({ projects: 1, tasks: 2, tags: 0, comments: 0 }, result[:imported])

    project = @user.projects.find_by(title: "Code - dev_scripts")
    assert project

    ready_task = project.tasks.find_by(title: "Fix mktemp templates")
    assert_equal @user, ready_task.user
    assert_equal "medium", ready_task.priority
    assert_equal "Ready to Test", ready_task.status.name
    assert_equal "Bump to 6+ X's for BusyBox.", ready_task.description

    not_started_task = project.tasks.find_by(title: "Add ngram command")
    assert_equal "Not Started", not_started_task.status.name
  end

  test "importing a TSV file tolerates a stray, unescaped quote inside a field" do
    tsv = "Title\tPriority\tStatus\tProject\tDescription\n" \
          "Fix mktemp templates\tmedium\tReady to Test\tCode - dev_scripts\t" \
          "rejected by BusyBox mktemp (\"Invalid argument\"). Fixed in ds:tmp().\n"

    result = UserDataService.import_data(@user, tsv_file(tsv), password: nil)

    assert result[:success], "Expected import to succeed, got error: #{result[:error]}"
    task = @user.projects.find_by(title: "Code - dev_scripts").tasks.find_by(title: "Fix mktemp templates")
    assert_equal 'rejected by BusyBox mktemp ("Invalid argument"). Fixed in ds:tmp().', task.description
  end

  test "importing a TSV file tolerates a trailing blank line" do
    tsv = "Title\tPriority\tStatus\tProject\tDescription\n" \
          "Solo task\tlow\tNot Started\tSolo Project\tJust one row.\n" \
          "\n"

    result = UserDataService.import_data(@user, tsv_file(tsv), password: nil)

    assert result[:success], "Expected import to succeed, got error: #{result[:error]}"
    assert_equal 1, result[:imported][:tasks]
  end

  test "importing a TSV task with a title similar to an existing sibling task does not fail" do
    @project.tasks.create!(user: @user, title: "Water plants (2026-01)", skip_duplicate_check: true)

    tsv = "Title\tPriority\tStatus\tProject\tDescription\n" \
          "Water plants (2026-02)\tmedium\tNot Started\t#{@project.title}\tWater again.\n"

    result = UserDataService.import_data(@user, tsv_file(tsv), password: nil)

    assert result[:success], "Expected import to succeed, got error: #{result[:error]}"
    assert @project.tasks.exists?(title: "Water plants (2026-01)")
    assert @project.tasks.exists?(title: "Water plants (2026-02)")
  end

  test "importing a TSV file with require_existing_projects rejects an unknown project and creates nothing" do
    tsv = "Title\tPriority\tStatus\tProject\tDescription\n" \
          "Fix mktemp templates\tmedium\tReady to Test\tCod - dev_scripts\tTypo'd project name.\n"

    result = UserDataService.import_data(@user, tsv_file(tsv), password: nil, require_existing_projects: true)

    refute result[:success]
    assert_includes result[:error], "Cod - dev_scripts"
    refute @user.projects.exists?(title: "Cod - dev_scripts")
  end

  test "importing a TSV file with require_existing_projects succeeds when the project already exists" do
    tsv = "Title\tPriority\tStatus\tProject\tDescription\n" \
          "New task\tmedium\tNot Started\t#{@project.title}\tGoes into the existing project.\n"

    result = UserDataService.import_data(@user, tsv_file(tsv), password: nil, require_existing_projects: true)

    assert result[:success], "Expected import to succeed, got error: #{result[:error]}"
    assert @project.tasks.exists?(title: "New task")
  end

  test "importing JSON with require_existing_projects rejects an unknown project and creates nothing" do
    data = {
      "export_info" => { "version" => "1.0" },
      "user" => { "id" => @user.id },
      "tags" => [],
      "projects" => [
        {
          "name" => "Brand New Project",
          "description" => "",
          "priority" => "medium",
          "statuses" => [],
          "tasks" => [],
          "comments" => []
        }
      ]
    }

    result = UserDataService.import_data(@user, json_file(data), password: nil, require_existing_projects: true)

    refute result[:success]
    assert_includes result[:error], "Brand New Project"
    refute @user.projects.exists?(title: "Brand New Project")
  end

  private

  def json_file(data)
    file = StringIO.new(data.to_json)
    file.define_singleton_method(:original_filename) { "export.json" }
    file
  end

  def tsv_file(content)
    file = StringIO.new(content)
    file.define_singleton_method(:original_filename) { "import.tsv" }
    file
  end
end
