require "test_helper"

class ProjectMembershipsControllerTest < ActionDispatch::IntegrationTest
  def setup
    ProjectsController.class_eval { layout 'test' }

    @owner = users(:one)
    @project = projects(:one)
    @other = users(:two)
    sign_in_as(@owner, skip_redirect: true)
    setup_paper_trail(@owner)
  end

  def teardown
    ProjectsController.class_eval { layout 'application' }
    teardown_paper_trail
  end

  test "the project settings page lists members and offers the add form" do
    ProjectMembership.create!(project: @project, user: @other, role: "manager")

    get edit_project_path(@project)

    assert_response :success
    assert_match @other.name, response.body
    assert_match I18n.t('views.projects.edit.members.title'), response.body
  end

  test "the owner can add a member" do
    assert_difference -> { @project.project_memberships.count }, 1 do
      post project_project_memberships_path(@project),
           params: { project_membership: { user_id: @other.id, role: "member" } }
    end

    assert_redirected_to edit_project_path(@project)
    assert_equal "member", @project.project_memberships.last.role
  end

  test "adding the owner is refused" do
    assert_no_difference -> { ProjectMembership.count } do
      post project_project_memberships_path(@project),
           params: { project_membership: { user_id: @owner.id, role: "member" } }
    end

    assert_redirected_to edit_project_path(@project)
  end

  test "a role can be changed" do
    membership = ProjectMembership.create!(project: @project, user: @other, role: "member")

    patch project_membership_path(membership), params: { project_membership: { role: "manager" } }

    assert_redirected_to edit_project_path(@project)
    assert_equal "manager", membership.reload.role
  end

  test "an update cannot point a membership at a different person" do
    membership = ProjectMembership.create!(project: @project, user: @other, role: "member")

    patch project_membership_path(membership),
          params: { project_membership: { user_id: users(:sorting_test_user).id, role: "manager" } }

    assert_equal @other.id, membership.reload.user_id
  end

  test "a member can be removed" do
    membership = ProjectMembership.create!(project: @project, user: @other, role: "member")

    assert_difference -> { ProjectMembership.count }, -1 do
      delete project_membership_path(membership)
    end

    assert_redirected_to edit_project_path(@project)
  end

  test "a plain member cannot manage the member list" do
    ProjectMembership.create!(project: @project, user: @other, role: "member")
    # reset! drops the owner's session; signing in again without it leaves the
    # original one in place and the request still acts as the owner.
    reset!
    sign_in_as(@other, skip_redirect: true)

    assert_no_difference -> { ProjectMembership.count } do
      post project_project_memberships_path(@project),
           params: { project_membership: { user_id: users(:sorting_test_user).id, role: "member" } }
    end

    assert_response :not_found
  end

  test "a manager who removes their own membership is sent somewhere they can still see" do
    membership = ProjectMembership.create!(project: @project, user: @other, role: "manager")
    reset!
    sign_in_as(@other, skip_redirect: true)

    delete project_membership_path(membership)

    assert_redirected_to projects_path
    assert_not @project.reload.collaborator?(@other)
  end
end
