class NotificationsController < ApplicationController
  PER_PAGE = 20

  before_action :set_notification, only: [:mark_read]

  def index
    @notifications = current_user.notifications.recent_first.page(params[:page]).per(PER_PAGE)
  end

  def mark_read
    @notification.mark_as_read!
    redirect_back fallback_location: notifications_path
  end

  def mark_all_read
    current_user.notifications.unread.update_all(read_at: Time.current)
    redirect_back fallback_location: notifications_path
  end

  private

  def set_notification
    @notification = current_user.notifications.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to notifications_path, alert: t('views.notifications.index.not_found')
  end
end
