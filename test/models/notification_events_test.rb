require "test_helper"

class NotificationEventsTest < ActiveSupport::TestCase
  def setup
    @owner = users(:one)
    @project = projects(:one)
    @member = users(:two)
    setup_paper_trail(@owner)
  end

  def teardown
    teardown_paper_trail
  end

  test "adding someone to a project notifies them" do
    assert_difference -> { @member.notifications.count }, 1 do
      ProjectMembership.create!(project: @project, user: @member, role: "member")
    end

    assert_equal "added_to_project", @member.notifications.last.kind
  end

  test "assigning a task to someone else notifies them" do
    ProjectMembership.create!(project: @project, user: @member, role: "member")
    task = @project.create_task!(title: "Assignment notice candidate", user: @owner)

    assert_difference -> { @member.notifications.where(kind: "task_assigned").count }, 1 do
      task.update!(user: @member)
    end
  end

  test "assigning a task to yourself notifies nobody" do
    task = @project.create_task!(title: "Self assignment candidate", user: nil)

    assert_no_difference -> { Notification.where(kind: "task_assigned").count } do
      task.update!(user: @owner)
    end
  end

  test "a comment notifies the assignee but never the commenter" do
    ProjectMembership.create!(project: @project, user: @member, role: "member")
    task = @project.create_task!(title: "Comment notice candidate", user: @member)

    assert_difference -> { @member.notifications.where(kind: "task_commented").count }, 1 do
      task.comments.create!(content: "Taking a look", user: @owner)
    end

    assert_no_difference -> { Notification.where(kind: "task_commented").count } do
      task.comments.create!(content: "Thanks", user: @member)
    end
  end

  test "an unassigned task's comments notify nobody" do
    task = @project.create_task!(title: "Nobody is on this one", user: nil)

    assert_no_difference -> { Notification.where(kind: "task_commented").count } do
      task.comments.create!(content: "Anyone?", user: @owner)
    end
  end
end
