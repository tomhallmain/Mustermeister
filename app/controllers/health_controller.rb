class HealthController < ApplicationController
  skip_before_action :authenticate_user!
  skip_before_action :verify_authenticity_token

  def show
    render json: { status: "ok" }, status: :ok
  end

  def backup_status
    backup_service = BackupService.new
    
    render json: {
      last_backup: backup_service.last_backup_time&.iso8601,
      time_since_last_backup: backup_service.time_since_last_backup,
      should_backup: backup_service.should_backup?,
      available_backups: backup_service.list_backups.count,
      backup_status: backup_service.should_backup? ? "needs_backup" : "up_to_date"
    }, status: :ok
  end
end 