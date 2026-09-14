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
      # result[:error] already reads "Export failed: ..." - UserDataService's
      # own rescue adds that prefix, so don't add it again here.
      redirect_to profile_path, alert: result[:error]
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
    require_existing_projects = ActiveModel::Type::Boolean.new.cast(params[:require_existing_projects])
    result = UserDataService.import_data(current_user, params[:file], password: password, require_existing_projects: require_existing_projects)
    
    if result[:success]
      imported = result[:imported]
      message = "Import successful! Imported #{imported[:projects]} projects, #{imported[:tasks]} tasks, #{imported[:tags]} tags, and #{imported[:comments]} comments."
      redirect_to profile_path, notice: message
    else
      # result[:error] already reads "Import failed: ..." - see export_data.
      redirect_to profile_path, alert: result[:error]
    end
  end

  def regenerate_api_token
    # Only the digest is stored, so this redirect is the one and only time the
    # token itself can be shown. The profile view reads it back out of flash.
    flash[:api_token] = current_user.regenerate_api_token!
    redirect_to profile_path, notice: t('views.users.profile.api_token_regenerated')
  end

  def update_api_token_scope
    if current_user.update(api_token_scope: params[:api_token_scope])
      redirect_to profile_path, notice: t('views.users.profile.api_token_scope_updated')
    else
      redirect_to profile_path, alert: t('views.users.profile.api_token_scope_invalid')
    end
  end

  private

  def user_params
    params.require(:user).permit(:name, :email, :theme_preference, :translate_target_language)
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