require "test_helper"

class StatusesControllerTest < ActionDispatch::IntegrationTest
  def setup
    StatusesController.class_eval do
      layout 'test'
    end

    @user = users(:one)
    @other_user = users(:two)
    @project = projects(:one)
    @other_project = projects(:two)
    sign_in_as(@user, skip_redirect: true)

    setup_paper_trail
  end

  def teardown
    StatusesController.class_eval do
      layout 'application'
    end

    teardown_paper_trail
  end

  test "should get new for own project" do
    get new_project_status_path(@project)
    assert_response :success
  end

  test "should create a custom status for own project" do
    assert_difference('Status.count') do
      post project_statuses_path(@project), params: { status: { name: "Blocked" } }
    end

    status = Status.find_by(name: "Blocked", project: @project)
    assert status
    assert_redirected_to edit_project_path(@project)
  end

  test "created status is appended after existing statuses" do
    highest = @project.statuses.maximum(:position)
    post project_statuses_path(@project), params: { status: { name: "Blocked" } }

    assert_equal highest + 1, Status.find_by(name: "Blocked", project: @project).position
  end

  test "should not create a status with a blank name" do
    assert_no_difference('Status.count') do
      post project_statuses_path(@project), params: { status: { name: "" } }
    end
    assert_response :unprocessable_entity
  end

  test "should not create a status for another user's project" do
    assert_no_difference('Status.count') do
      post project_statuses_path(@other_project), params: { status: { name: "Blocked" } }
    end
    assert_response :not_found
  end

  test "should get edit for a custom status" do
    custom = @project.statuses.create!(name: "Blocked")
    get edit_status_path(custom)
    assert_response :success
  end

  test "should update a custom status" do
    custom = @project.statuses.create!(name: "Blocked")
    patch status_path(custom), params: { status: { name: "Waiting" } }
    assert_redirected_to edit_project_path(@project)
    assert_equal "Waiting", custom.reload.name
  end

  test "should destroy a custom status not in use" do
    custom = @project.statuses.create!(name: "Blocked")
    assert_difference('Status.count', -1) do
      delete status_path(custom)
    end
    assert_redirected_to edit_project_path(@project)
  end

  test "should not destroy a custom status assigned to a task" do
    custom = @project.statuses.create!(name: "Blocked")
    @project.tasks.create!(title: "Blocked task", user: @user, status: custom, skip_duplicate_check: true)

    assert_no_difference('Status.count') do
      delete status_path(custom)
    end
    assert_redirected_to edit_project_path(@project)
  end

  test "should not edit a default status" do
    default_status = statuses(:project_one_not_started)
    get edit_status_path(default_status)
    assert_redirected_to edit_project_path(@project)
  end

  test "should not update a default status" do
    default_status = statuses(:project_one_not_started)
    patch status_path(default_status), params: { status: { name: "Renamed" } }
    assert_redirected_to edit_project_path(@project)
    assert_equal "Not Started", default_status.reload.name
  end

  test "should not destroy a default status" do
    default_status = statuses(:project_one_not_started)
    assert_no_difference('Status.count') do
      delete status_path(default_status)
    end
    assert_redirected_to edit_project_path(@project)
  end

  test "should not manage another user's status" do
    other_default = statuses(:project_two_not_started)
    get edit_status_path(other_default)
    assert_redirected_to root_path
  end

  test "move_up swaps position with the previous status" do
    first = statuses(:project_one_not_started)
    second = statuses(:project_one_in_progress)
    original_first_position = first.position
    original_second_position = second.position

    patch move_up_status_path(second)

    assert_equal original_first_position, second.reload.position
    assert_equal original_second_position, first.reload.position
  end

  test "move_down swaps position with the next status, including for a default status" do
    first = statuses(:project_one_not_started)
    second = statuses(:project_one_in_progress)
    original_first_position = first.position
    original_second_position = second.position

    patch move_down_status_path(first)

    assert_equal original_second_position, first.reload.position
    assert_equal original_first_position, second.reload.position
  end

  test "creating a status bumps the project's last_activity_at" do
    @project.update_column(:last_activity_at, 1.day.ago)
    post project_statuses_path(@project), params: { status: { name: "Blocked" } }
    assert_operator @project.reload.last_activity_at, :>, 1.day.ago
  end

  test "updating a status bumps the project's last_activity_at" do
    custom = @project.statuses.create!(name: "Blocked")
    @project.update_column(:last_activity_at, 1.day.ago)

    patch status_path(custom), params: { status: { name: "Waiting" } }

    assert_operator @project.reload.last_activity_at, :>, 1.day.ago
  end

  test "destroying a status bumps the project's last_activity_at" do
    custom = @project.statuses.create!(name: "Blocked")
    @project.update_column(:last_activity_at, 1.day.ago)

    delete status_path(custom)

    assert_operator @project.reload.last_activity_at, :>, 1.day.ago
  end

  test "a blocked destroy (status still in use) does not bump the project's activity" do
    custom = @project.statuses.create!(name: "Blocked")
    @project.tasks.create!(title: "Blocked task", user: @user, status: custom, skip_duplicate_check: true)
    @project.update_column(:last_activity_at, 1.day.ago)

    delete status_path(custom)

    assert_in_delta 1.day.ago.to_i, @project.reload.last_activity_at.to_i, 2
  end

  test "moving a status bumps the project's last_activity_at" do
    second = statuses(:project_one_in_progress)
    @project.update_column(:last_activity_at, 1.day.ago)

    patch move_up_status_path(second)

    assert_operator @project.reload.last_activity_at, :>, 1.day.ago
  end

  test "a no-op move does not bump the project's activity" do
    first_status = statuses(:project_one_not_started)
    @project.update_column(:last_activity_at, 1.day.ago)

    patch move_up_status_path(first_status)

    assert_in_delta 1.day.ago.to_i, @project.reload.last_activity_at.to_i, 2
  end
end
