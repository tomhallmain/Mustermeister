require "test_helper"

class TaskIndexQueryTest < ActiveSupport::TestCase
  def setup
    @user = users(:one)
    setup_paper_trail(@user)
    @project = Project.create!(title: "Task Index Query Project", user: @user)
  end

  def teardown
    teardown_paper_trail
  end

  def run_query(**overrides)
    options = {
      scope: @project.tasks,
      show_completed: true,
      search: nil,
      sort_by: TaskIndexQuery::DEFAULT_SORT,
      page: nil
    }
    TaskIndexQuery.new(**options.merge(overrides)).call
  end

  def create_task(title, **attrs)
    @project.tasks.create!(title: title, user: @user, skip_duplicate_check: true, **attrs)
  end

  test "excludes archived tasks" do
    visible = create_task("Visible")
    archived = create_task("Archived")
    archived.update_columns(archived: true, archived_at: Time.current)

    results = run_query.to_a

    assert_includes results, visible
    assert_not_includes results, archived
  end

  test "hides completed tasks unless show_completed is set" do
    active = create_task("Active")
    done = create_task("Done", completed: true)

    assert_equal [active], run_query(show_completed: false).to_a
    assert_equal [active, done].sort_by(&:id), run_query(show_completed: true).to_a.sort_by(&:id)
  end

  test "active_oldest_completed_newest lists active tasks oldest first, then completed tasks newest first" do
    active_old = create_task("Active old")
    active_new = create_task("Active new")
    done_old = create_task("Done old", completed: true)
    done_new = create_task("Done new", completed: true)
    active_old.update_columns(updated_at: 3.days.ago)
    active_new.update_columns(updated_at: 1.day.ago)
    done_old.update_columns(updated_at: 3.days.ago)
    done_new.update_columns(updated_at: 1.day.ago)

    results = run_query(sort_by: TaskIndexQuery::ACTIVE_OLDEST_SORT).to_a

    assert_equal [active_old, active_new, done_new, done_old], results
  end

  test "search narrows the list and keeps the search ranking" do
    word_prefix = create_task("Feed the quokka")
    title_prefix = create_task("Quokka census")
    create_task("Unrelated")

    assert_equal [title_prefix, word_prefix], run_query(search: "quokka").to_a
  end

  test "pages at PER_PAGE" do
    assert_equal TaskIndexQuery::PER_PAGE, run_query.limit_value
  end

  test "valid_sort falls back to the default for an unrecognized value" do
    assert_equal TaskIndexQuery::ACTIVE_OLDEST_SORT, TaskIndexQuery.valid_sort(TaskIndexQuery::ACTIVE_OLDEST_SORT)
    assert_equal TaskIndexQuery::DEFAULT_SORT, TaskIndexQuery.valid_sort("not_a_real_option")
    assert_equal TaskIndexQuery::DEFAULT_SORT, TaskIndexQuery.valid_sort(nil)
  end
end
