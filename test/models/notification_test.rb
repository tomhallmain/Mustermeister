require "test_helper"

class NotificationTest < ActiveSupport::TestCase
  def setup
    @user = users(:one)
  end

  test "requires a title" do
    notification = Notification.new(user: @user, title: nil)
    assert_not notification.valid?
    assert_includes notification.errors[:title], "can't be blank"
  end

  test "notify! creates an unread notification for the user" do
    notification = Notification.notify!(user: @user, title: "Hello", body: "World", kind: "test", link_path: "/somewhere")

    assert_equal @user, notification.user
    assert_equal "Hello", notification.title
    assert_not notification.read?
    assert_includes Notification.unread, notification
  end

  test "mark_as_read! sets read_at and read? becomes true" do
    notification = Notification.notify!(user: @user, title: "Hello")

    assert_changes -> { notification.reload.read_at } do
      notification.mark_as_read!
    end
    assert notification.read?
    assert_not_includes Notification.unread, notification
  end

  test "mark_as_read! is a no-op if already read" do
    notification = Notification.notify!(user: @user, title: "Hello")
    notification.mark_as_read!
    read_at = notification.read_at

    notification.mark_as_read!
    assert_equal read_at, notification.reload.read_at
  end

  test "recent_first orders newest first" do
    older = Notification.notify!(user: @user, title: "Older")
    older.update_column(:created_at, 2.days.ago)
    newer = Notification.notify!(user: @user, title: "Newer")
    newer.update_column(:created_at, 1.hour.ago)

    assert_equal [newer, older], @user.notifications.recent_first.to_a
  end
end
