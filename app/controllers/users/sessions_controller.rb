class Users::SessionsController < Devise::SessionsController
  before_action :set_request_format
  before_action :check_rate_limit, only: [:create]

  def new
    self.resource = resource_class.new(sign_in_params)
    clean_up_passwords(resource)
    yield resource if block_given?
    
    respond_to do |format|
      format.html { super }
      format.json { render json: { error: "You need to sign in or sign up before continuing." }, status: :unauthorized }
    end
  end

  def create
    self.resource = warden.authenticate!(auth_options)
    set_flash_message!(:notice, :signed_in)
    sign_in(resource_name, resource)
    yield resource if block_given?
    
    respond_to do |format|
      format.json { render json: { message: "Signed in successfully.", user: resource }, status: :ok }
      format.html { respond_with resource, location: after_sign_in_path_for(resource) }
    end
  rescue Warden::AuthenticationError
    increment_failed_attempts
    respond_to do |format|
      format.json { render json: { error: "Invalid email or password." }, status: :unauthorized }
      format.html { super }
    end
  end

  def destroy
    signed_out = (Devise.sign_out_all_scopes ? sign_out : sign_out(resource_name))
    set_flash_message! :notice, :signed_out if signed_out
    yield if block_given?
    
    respond_to do |format|
      format.json { render json: { message: "Signed out successfully." }, status: :ok }
      format.html { redirect_to after_sign_out_path_for(resource_name) }
    end
  end

  private

  def set_request_format
    request.format = :html if request.format == Mime[:json] && request.headers['HTTP_ACCEPT'].include?('text/html')
  end

  def check_rate_limit
    if too_many_attempts?
      respond_to do |format|
        format.json { render json: { error: "Too many login attempts. Please try again later." }, status: :too_many_requests }
        format.html { redirect_to new_user_session_path, alert: "Too many login attempts. Please try again later." }
      end
    end
  end

  def too_many_attempts?
    Rails.cache.read(failed_attempts_key).to_i >= 5
  end

  def increment_failed_attempts
    Rails.cache.increment(failed_attempts_key, 1, expires_in: 1.hour)
  end

  def failed_attempts_key
    "failed_login_attempts:#{request.remote_ip}"
  end
end 