class Users::SessionsController < Devise::SessionsController
  before_action :set_request_format

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
end 