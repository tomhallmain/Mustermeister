class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  before_action :authenticate_user!
  before_action :configure_permitted_parameters, if: :devise_controller?
  before_action :set_session_timeout

  protected

  def configure_permitted_parameters
    devise_parameter_sanitizer.permit(:sign_up, keys: [:name])
    devise_parameter_sanitizer.permit(:account_update, keys: [:name])
  end

  private

  def set_session_timeout
    if current_user && session[:last_seen_at] && session[:last_seen_at] < 30.minutes.ago
      sign_out current_user
      flash[:alert] = "Your session has expired. Please sign in again."
      redirect_to new_user_session_path
    end
    session[:last_seen_at] = Time.current
  end
end
