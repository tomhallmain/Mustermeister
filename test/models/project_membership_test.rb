require "test_helper"

class ProjectMembershipTest < ActiveSupport::TestCase
  def setup
    @project = projects(:one)
    @member = users(:two)
    setup_paper_trail(users(:one))
  end

  def teardown
    teardown_paper_trail
  end

  test "accepts every known role" do
    ProjectMembership::ROLES.each do |role|
      membership = ProjectMembership.new(project: @project, user: @member, role: role)

      assert membership.valid?, "expected #{role.inspect} to be a valid role"
    end
  end

  test "rejects an unknown role" do
    membership = ProjectMembership.new(project: @project, user: @member, role: "owner")

    assert_not membership.valid?
  end

  test "defaults to the member role" do
    membership = ProjectMembership.create!(project: @project, user: @member)

    assert_equal "member", membership.role
    assert_not membership.manager?
  end

  test "a user cannot join the same project twice" do
    ProjectMembership.create!(project: @project, user: @member)
    duplicate = ProjectMembership.new(project: @project, user: @member)

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:user_id],
                    I18n.t('activerecord.errors.models.project_membership.attributes.user_id.taken')
  end

  test "the project owner cannot also hold a membership" do
    membership = ProjectMembership.new(project: @project, user: @project.user)

    assert_not membership.valid?
    assert_includes membership.errors[:user],
                    I18n.t('activerecord.errors.models.project_membership.attributes.user.is_project_owner')
  end

  test "removing a member unassigns their tasks in that project" do
    membership = ProjectMembership.create!(project: @project, user: @member)
    task = @project.create_task!(title: "Work handed to a member", user: @member)

    membership.destroy

    assert_nil task.reload.user_id
  end

  test "memberships go away with their project" do
    project = Project.create!(title: "Membership teardown project", user: users(:one), confirm_duplicate: true)
    ProjectMembership.create!(project: project, user: @member)

    assert_difference -> { ProjectMembership.count }, -1 do
      project.destroy
    end
  end
end
