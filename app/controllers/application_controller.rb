class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Must stay below the session cookie's own expire_after, so that an idle
  # session is caught here while the cookie is still valid. Matching that value
  # would make this check unreachable: the cookie stops being sent first,
  # current_user goes nil, and Devise rejects the request before it runs.
  SESSION_IDLE_TIMEOUT = 30.minutes

  before_action :authenticate_user!
  before_action :set_paper_trail_whodunnit
  before_action :configure_permitted_parameters, if: :devise_controller?
  before_action :set_session_timeout
  before_action :set_locale

  protected

  def configure_permitted_parameters
    devise_parameter_sanitizer.permit(:sign_up, keys: [:name])
    devise_parameter_sanitizer.permit(:account_update, keys: [:name])
  end

  private

  def set_session_timeout
    if current_user && session[:last_seen_at] && session[:last_seen_at] < SESSION_IDLE_TIMEOUT.ago
      sign_out current_user
      respond_with_expired_session
    end
    session[:last_seen_at] = Time.current
  end

  def handle_unverified_request
    sign_out current_user if current_user
    respond_with_expired_session
  end

  # A JSON caller gets a 401 it can act on. Redirecting it to the sign-in page
  # instead would reach fetch as a 200 carrying HTML, since fetch follows the
  # redirect on its own and the caller sees only the final response.
  def respond_with_expired_session
    message = t('application.messages.session_expired')

    if request.format.json?
      render json: { error: message }, status: :unauthorized
    else
      flash[:alert] = message
      redirect_to new_user_session_path
    end
  end

  def set_locale
    I18n.locale = params[:locale] || 
                 session[:locale] || 
                 http_accept_language.compatible_language_from(I18n.available_locales) ||
                 I18n.default_locale
    session[:locale] = I18n.locale
  end

  def set_paper_trail_whodunnit
    PaperTrail.request.whodunnit = current_user&.id
    PaperTrail.request.controller_info = {
      ip: request.remote_ip,
      user_agent: request.user_agent
    }
  end

  def default_url_options
    { locale: I18n.locale == I18n.default_locale ? nil : I18n.locale }
  end
end
