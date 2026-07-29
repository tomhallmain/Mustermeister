require "test_helper"

class StatusTest < ActiveSupport::TestCase
  def setup
    @project = projects(:one)
    @status = Status.new(name: "Test Status", project: @project)
  end

  test "should be valid" do
    assert @status.valid?
  end

  test "name should be present" do
    @status.name = nil
    assert_not @status.valid?
  end

  test "project should be present" do
    @status.project = nil
    assert_not @status.valid?
  end

  test "name should be unique within project" do
    duplicate_status = @status.dup
    @status.save
    assert_not duplicate_status.valid?
  end

  test "same name can exist in different projects" do
    other_project = projects(:two)
    @status.save
    other_status = Status.new(name: @status.name, project: other_project)
    assert other_status.valid?
  end

  test "default_statuses returns correct hash" do
    default_statuses = Status.default_statuses
    assert_kind_of Hash, default_statuses
    assert_includes default_statuses.keys, :not_started
    assert_includes default_statuses.keys, :in_progress
    assert_includes default_statuses.keys, :complete
  end

  test "default_statuses has correct values" do
    default_statuses = Status.default_statuses
    assert_equal "Not Started", default_statuses[:not_started]
    assert_equal "In Progress", default_statuses[:in_progress]
    assert_equal "Complete", default_statuses[:complete]
  end

  test "default? returns true for default statuses" do
    @status.name = Status.default_statuses[:not_started]
    assert @status.default?
  end

  test "default? returns false for custom statuses" do
    @status.name = "Custom Status"
    assert_not @status.default?
  end

  test "default_key returns correct key for default statuses" do
    @status.name = Status.default_statuses[:not_started]
    assert_equal :not_started, @status.default_key
  end

  test "default_key returns nil for custom statuses" do
    @status.name = "Custom Status"
    assert_nil @status.default_key
  end

  test "position is auto-assigned on create, appended after existing statuses" do
    highest = @project.statuses.maximum(:position)
    @status.save!
    assert_equal highest + 1, @status.position
  end

  test "position is not overwritten if already set" do
    @status.position = 99
    @status.save!
    assert_equal 99, @status.position
  end

  test "ordered scope sorts by position then id" do
    project = Project.create!(title: "Fresh Project", user: @project.user, confirm_duplicate: true)
    project.statuses.destroy_all
    third = Status.create!(name: "Third", project: project, position: 2)
    first = Status.create!(name: "First", project: project, position: 0)
    second = Status.create!(name: "Second", project: project, position: 1)

    assert_equal [first, second, third], project.statuses.ordered.to_a
  end

  test "custom scope excludes default-named statuses" do
    @status.name = "Custom Status"
    @status.save!
    default_status = @project.statuses.find { |s| s.default? }

    assert_includes @project.statuses.custom, @status
    assert_not_includes @project.statuses.custom, default_status
  end

  test "in_use? reflects whether any task has this status" do
    @status.save!
    assert_not @status.in_use?

    Task.create!(title: "Uses it", project: @project, user: @project.user, status: @status, skip_duplicate_check: true)
    assert @status.in_use?
  end

  test "move_earlier swaps position with the previous status" do
    project = Project.create!(title: "Fresh Project", user: @project.user, confirm_duplicate: true)
    project.statuses.destroy_all
    first = Status.create!(name: "First", project: project, position: 0)
    second = Status.create!(name: "Second", project: project, position: 1)

    second.move_earlier

    assert_equal [second.reload, first.reload], project.statuses.ordered.to_a
  end

  test "move_earlier is a no-op at the start of the list" do
    project = Project.create!(title: "Fresh Project", user: @project.user, confirm_duplicate: true)
    project.statuses.destroy_all
    first = Status.create!(name: "First", project: project, position: 0)
    Status.create!(name: "Second", project: project, position: 1)

    first.move_earlier

    assert_equal 0, first.reload.position
  end

  test "move_later swaps position with the next status" do
    project = Project.create!(title: "Fresh Project", user: @project.user, confirm_duplicate: true)
    project.statuses.destroy_all
    first = Status.create!(name: "First", project: project, position: 0)
    second = Status.create!(name: "Second", project: project, position: 1)

    first.move_later

    assert_equal [second.reload, first.reload], project.statuses.ordered.to_a
  end

  test "move_later is a no-op at the end of the list" do
    project = Project.create!(title: "Fresh Project", user: @project.user, confirm_duplicate: true)
    project.statuses.destroy_all
    Status.create!(name: "First", project: project, position: 0)
    second = Status.create!(name: "Second", project: project, position: 1)

    second.move_later

    assert_equal 1, second.reload.position
  end
end 