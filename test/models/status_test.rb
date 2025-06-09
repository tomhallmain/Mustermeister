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
end 