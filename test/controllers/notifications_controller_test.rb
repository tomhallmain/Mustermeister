require "test_helper"

class NotificationsControllerTest < ActionDispatch::IntegrationTest
  def setup
    NotificationsController.class_eval do
      layout 'test'
    end

    @user = users(:one)
    @other_user = users(:two)
    sign_in_as(@user, skip_redirect: true)
  end

  def teardown
    NotificationsController.class_eval do
      layout 'application'
    end
  end

  test "index only lists the current user's own notifications" do
    mine = Notification.notify!(user: @user, title: "Mine")
    Notification.notify!(user: @other_user, title: "Not Mine")

    get notifications_path
    assert_response :success
    assert_match mine.title, response.body
    assert_no_match(/Not Mine/, response.body)
  end

  test "mark_read marks a single notification as read" do
    notification = Notification.notify!(user: @user, title: "Mine")

    patch mark_read_notification_path(notification)
    assert notification.reload.read?
  end

  test "cannot mark another user's notification as read" do
    notification = Notification.notify!(user: @other_user, title: "Not Mine")

    patch mark_read_notification_path(notification)
    assert_not notification.reload.read?
  end

  test "mark_all_read marks every unread notification for the user as read" do
    a = Notification.notify!(user: @user, title: "A")
    b = Notification.notify!(user: @user, title: "B")
    other = Notification.notify!(user: @other_user, title: "Other")

    patch mark_all_read_notifications_path

    assert a.reload.read?
    assert b.reload.read?
    assert_not other.reload.read?
  end
end
