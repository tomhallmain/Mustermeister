require "application_system_test_case"

class KanbanSearchTest < ApplicationSystemTestCase
  def setup
    @user = users(:one)
    @project = projects(:one)
    @project.create_default_statuses! # Ensure default statuses are created
    setup_paper_trail(@user)
    sign_in_as(@user)
  end

  def teardown
    teardown_paper_trail
  end

  test "search finds a task beyond the first loaded page of results" do
    not_started = @project.status_by_key(:not_started)
    # Created first, so it's the oldest by updated_at (the board's default
    # sort) and sits past the first 100-per-column page once the bulk tasks
    # below (all newer) are created - invisible until searched for.
    needle = @project.tasks.create!(title: "Findable Needle Task", user: @user, status: not_started)
    101.times { |i| @project.tasks.create!(title: "Bulk Task #{i}", user: @user, status: not_started, skip_duplicate_check: true) }

    visit kanban_path
    assert_no_text needle.title

    fill_in "search-input", with: "Findable Needle"

    assert_text needle.title
  end

  test "search only matches at a word boundary, not mid-word" do
    not_started = @project.status_by_key(:not_started)
    boundary_match = @project.tasks.create!(title: "Q1-Quarterly Numbers", user: @user, status: not_started)
    mid_word = @project.tasks.create!(title: "Requarterly Task", user: @user, status: not_started, skip_duplicate_check: true)

    visit kanban_path
    fill_in "search-input", with: "quarterly"

    assert_text boundary_match.title
    assert_no_text mid_word.title
  end
end
