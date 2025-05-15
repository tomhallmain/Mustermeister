class ProjectsController < ApplicationController
  TASKS_PER_PAGE = 15

  before_action :initialize_show_completed_prefs
  before_action :set_project, only: [:show, :edit, :update, :destroy, :report]

  def index
    @projects = current_user.projects.includes(:tasks)
                          .order(last_activity_at: :desc)
                          .page(params[:page]).per(12)
  end

  def report
    @tasks = @project.tasks.not_completed
                    .includes(:tags)
                    .order(created_at: :desc)
  end

  def all_reports
    @projects = current_user.projects.not_completed
                          .includes(tasks: :tags)
                          .order(updated_at: :desc)
  end

  def show
    # Initialize preferences for this project if not already set
    session[:projects_show_completed] ||= {}
    
    # Debug values on entry
    Rails.logger.debug "ENTRY params[:show_completed]: #{params[:show_completed].inspect}"
    Rails.logger.debug "ENTRY session value: #{session[:projects_show_completed][@project.id.to_s].inspect}"
    
    # Add headers to disable Turbo for this response to prevent double requests
    response.headers["Turbo-Frame"] = "_top"
    response.headers["X-Robots-Tag"] = "none"
    
    # If show_completed param is present, update the session preference
    if params[:show_completed].present?
      show_completed = params[:show_completed] == 'true'
      Rails.logger.debug "UPDATING session to: #{show_completed.inspect}"
      session[:projects_show_completed][@project.id.to_s] = show_completed
    end
    
    # Get the current stored preference (default to false if nil)
    stored_preference = session[:projects_show_completed][@project.id.to_s]
    stored_preference = false if stored_preference.nil?
    
    Rails.logger.debug "STORED preference: #{stored_preference.inspect}"
    
    # If no param and we have a stored preference, redirect to include it
    if params[:show_completed].nil?
      redirect_url = project_path(@project, show_completed: stored_preference, page: params[:page])
      Rails.logger.debug "REDIRECTING to: #{redirect_url}"
      redirect_to redirect_url
      return
    end
    
    # Add more debug info for the params
    Rails.logger.debug "Request referrer: #{request.referrer.inspect}"
    Rails.logger.debug "Request headers: #{request.headers.env.select {|k,v| k.start_with?('HTTP_')}.inspect}"
    
    # Current preference is from params (already stored in session above)
    current_preference = params[:show_completed] == 'true'
    
    Rails.logger.debug "CURRENT preference for tasks: #{current_preference.inspect}"
    
    # Now load the tasks based on the current preference
    @tasks = @project.tasks.includes(:tags, :user)
    @tasks = @tasks.not_completed unless current_preference
    @tasks = @tasks.order(created_at: :desc)
                   .page(params[:page]).per(TASKS_PER_PAGE)
  end

  def new
    @project = current_user.projects.build
  end

  def create
    @project = current_user.projects.build(project_params)

    if @project.save
      redirect_to @project, notice: 'Project was successfully created.'
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    old_due_date = @project.due_date
    
    if @project.update(project_params)
      # Check if due date changed and reschedule tasks if needed
      if @project.due_date != old_due_date
        begin
          updated_count = TaskManagementService.reschedule_project_tasks(
            project: @project,
            old_due_date: old_due_date,
            new_due_date: @project.due_date,
            current_user: current_user
          )
          
          notice = "Project was successfully updated. "
          notice += "#{updated_count} tasks were rescheduled." if updated_count > 0
          
          redirect_to @project, notice: notice
        rescue TaskManagementService::Error => e
          # If task rescheduling fails, we should still save the project update
          # but inform the user about the rescheduling failure
          redirect_to @project, 
            notice: "Project was updated but task rescheduling failed: #{e.message}"
        end
      else
        redirect_to @project, notice: 'Project was successfully updated.'
      end
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @project.destroy
    redirect_to projects_path, notice: 'Project was successfully deleted.'
  end

  private

  def initialize_show_completed_prefs
    session[:projects_show_completed] ||= {}
  end

  def set_project
    @project = current_user.projects.includes(:tasks).find(params[:id])
  end

  def project_params
    params.require(:project).permit(:title, :description, :due_date, :default_priority)
  end
end 