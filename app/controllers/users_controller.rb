class UsersController < ApplicationController
  before_action :authenticate_user!

  def profile
    # The profile view will use current_user
  end

  def update
    if current_user.update(user_params)
      redirect_to profile_path, notice: 'Profile was successfully updated.'
    else
      render :profile, status: :unprocessable_entity
    end
  end

  def export_data
    format = params[:format] || 'json'
    password = params[:password] if format == 'encrypted_zip'
    
    result = UserDataService.export_data(current_user, format: format, password: password)
    
    if result[:success]
      send_data result[:data], 
                filename: result[:filename],
                type: get_content_type(format),
                disposition: 'attachment'
    else
      redirect_to profile_path, alert: "Export failed: #{result[:error]}"
    end
  end

  def import_data
    unless params[:file]
      redirect_to profile_path, alert: 'Please select a file to import.'
      return
    end

    # Validate file
    validation = UserDataService.validate_import_file(params[:file])
    unless validation[:valid]
      redirect_to profile_path, alert: validation[:error]
      return
    end

    password = params[:password] if validation[:format] == '.zip'
    result = UserDataService.import_data(current_user, params[:file], password: password)
    
    if result[:success]
      imported = result[:imported]
      message = "Import successful! Imported #{imported[:projects]} projects, #{imported[:tasks]} tasks, #{imported[:tags]} tags, and #{imported[:comments]} comments."
      redirect_to profile_path, notice: message
    else
      redirect_to profile_path, alert: "Import failed: #{result[:error]}"
    end
  end

  private

  def user_params
    params.require(:user).permit(:name, :email, :theme_preference)
  end

  def get_content_type(format)
    case format
    when 'json'
      'application/json'
    when 'encrypted_zip'
      'application/zip'
    else
      'application/octet-stream'
    end
  end
end 