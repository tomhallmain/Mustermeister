require "test_helper"

class TimestampUpdatesTest < ActionDispatch::IntegrationTest
  def setup
    @user = users(:one)
    @project = projects(:one)
    @task = tasks(:one)
    @comment = comments(:one)
    @tag = tags(:one)
    
    # Simulate controller context for PaperTrail
    setup_paper_trail(ip: "192.168.1.1", user_agent: "TestAgent")
  end

  def teardown
    teardown_paper_trail
  end

  test "should update project update_at upon update" do
    original_updated_at = @project.updated_at
    sleep(1)
    @project.update!(title: "Updated Project Title")
    assert_not_equal original_updated_at, @project.updated_at
  end

  test "should update project last_activity_at when task is updated" do
    original_activity_at = @project.last_activity_at
    sleep(1)
    @task.update!(title: "Updated Task Title")
    @project.reload
    assert_not_equal original_activity_at, @project.last_activity_at
    assert_in_delta Time.current, @project.last_activity_at, 1.second
  end

  test "should update task timestamps" do
    original_updated_at = @task.updated_at
    sleep(1)
    @task.update!(title: "Updated Task Title")
    assert_not_equal original_updated_at, @task.updated_at
  end

  test "should update comment timestamps" do
    original_updated_at = @comment.updated_at
    sleep(1)
    @comment.update!(content: "Updated Comment Content")
    assert_not_equal original_updated_at, @comment.updated_at
  end

  test "should update tag timestamps" do
    original_updated_at = @tag.updated_at
    sleep(1)
    @tag.update!(name: "Updated Tag Name")
    assert_not_equal original_updated_at, @tag.updated_at
  end

  test "should track project versions" do
    assert_difference -> { @project.versions.count } do
      @project.update!(title: "New Project Title")
    end
    
    last_version = @project.versions.last
    assert_not_nil last_version
    assert_equal @user.id.to_s, last_version.whodunnit
    assert_equal "192.168.1.1", last_version.ip
    assert_equal "TestAgent", last_version.user_agent
  end

  test "should track task versions" do
    assert_difference -> { @task.versions.count } do
      @task.update!(title: "New Task Title")
    end
    last_version = @task.versions.last
    assert_equal @user.id, last_version.user_id
    assert_equal "192.168.1.1", last_version.ip
    assert_equal "TestAgent", last_version.user_agent
  end

  test "should track comment versions" do
    assert_difference -> { @comment.versions.count } do
      @comment.update!(content: "New Comment Content")
    end
    last_version = @comment.versions.last
    assert_equal @user.id, last_version.user_id
    assert_equal "192.168.1.1", last_version.ip
    assert_equal "TestAgent", last_version.user_agent
  end
end 