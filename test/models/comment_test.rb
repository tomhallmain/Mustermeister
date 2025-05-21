require "test_helper"

class CommentTest < ActiveSupport::TestCase
  def setup
    @user = users(:one)
    @task = tasks(:one)
    @project = projects(:one)
    @comment = comments(:one)

    # Simulate controller context for PaperTrail
    setup_paper_trail(ip: "192.168.1.1", user_agent: "TestAgent")
  end

  def teardown
    teardown_paper_trail
  end

  test "should be valid" do
    assert @comment.valid?
  end

  test "should require content" do
    @comment.content = nil
    assert_not @comment.valid?
    assert_includes @comment.errors[:content], "can't be blank"
  end

  test "should require user" do
    @comment.user = nil
    assert_not @comment.valid?
    assert_includes @comment.errors[:user], "must exist"
  end

  test "should require either task or project" do
    @comment.task = nil
    @comment.project = nil
    assert_not @comment.valid?
    assert_includes @comment.errors[:base], "Comment must belong to either a task or a project"
  end

  test "should not allow both task and project" do
    @comment.task = @task
    @comment.project = @project
    assert_not @comment.valid?
    assert_includes @comment.errors[:base], "Comment cannot belong to both a task and a project"
  end

  test "should belong to task" do
    @comment.task = @task
    @comment.project = nil
    assert @comment.valid?
  end

  test "should belong to project" do
    @comment.task = nil
    @comment.project = @project
    assert @comment.valid?
  end

  test "should have timestamps" do
    assert_respond_to @comment, :created_at
    assert_respond_to @comment, :updated_at
  end

  test "should track version with metadata on update" do
    @comment.update!(content: "New content")
    last_version = @comment.versions.last

    # Assert metadata is captured
    assert_equal @user.id, last_version.user_id
    assert_equal "192.168.1.1", last_version.ip
    assert_equal "TestAgent", last_version.user_agent
  end

  test "should update timestamps on save" do
    original_updated_at = @comment.updated_at
    sleep(1)
    @comment.update!(content: "Updated content")
    assert_not_equal original_updated_at, @comment.updated_at
  end
end
