class ProjectsController < ApplicationController
  PROJECTS_PER_PAGE = 12
  TASKS_PER_PAGE = 15

  before_action :initialize_show_completed_prefs
  before_action :set_project, only: [:show, :edit, :update, :destroy, :report, :reprioritize]

  def index
    @projects = current_user.projects.includes(:tasks)
    
    if params[:search].present?
      search_term = params[:search]
      @projects = @projects.where("title ILIKE ? OR description ILIKE ?", 
                                "%#{search_term}%", 
                                "%#{search_term}%")
                          .order(Arel.sql("
                            CASE 
                              WHEN title ILIKE '#{search_term}%' THEN 1
                              WHEN title ILIKE '% #{search_term}%' THEN 2
                              ELSE 3
                            END,
                            last_activity_at DESC"))
    else
      @projects = @projects.order(last_activity_at: :desc)
    end
    
    @projects = @projects.page(params[:page]).per(PROJECTS_PER_PAGE)
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
    @tasks = @project.tasks

    if params[:search].present?
      search_term = params[:search]
      @tasks = @tasks.where("title ILIKE ? OR description ILIKE ?", 
                           "%#{search_term}%", 
                           "%#{search_term}%")
                     .order(Arel.sql("
                       CASE 
                         WHEN title ILIKE '#{search_term}%' THEN 1
                         WHEN title ILIKE '% #{search_term}%' THEN 2
                         ELSE 3
                       END,
                       created_at DESC"))
    end

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
      session[:projects_show_completed][@project.id.to_s] = show_completed
    end
    
    # Get the current stored preference (default to false if nil)
    stored_preference = session[:projects_show_completed][@project.id.to_s]
    stored_preference = false if stored_preference.nil?
    
    # If no param and we have a stored preference, redirect to include it
    if params[:show_completed].nil?
      redirect_url = project_path(@project, show_completed: stored_preference, page: params[:page])
      Rails.logger.debug "REDIRECTING to: #{redirect_url}"
      redirect_to redirect_url
      return
    end
    
    # Current preference is from params (already stored in session above)
    current_preference = params[:show_completed] == 'true'
    
    # Now load the tasks based on the current preference
    @tasks = @tasks.includes(:tags, :user)
    @tasks = @tasks.not_completed unless current_preference
    @tasks = @tasks.order(Arel.sql('COALESCE(updated_at, created_at) DESC, created_at DESC'))
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

  def reprioritize
    begin
      updated_count = TaskManagementService.reprioritize_project_tasks(
        project: @project,
        current_user: current_user
      )
      
      notice = if updated_count > 0
        "Successfully updated #{updated_count} tasks to match project's default priority."
      else
        "No tasks needed priority updates."
      end
      
      redirect_to project_path(@project), notice: notice
    rescue TaskManagementService::Error => e
      redirect_to project_path(@project), alert: "Failed to reprioritize tasks: #{e.message}"
    end
  end

  private

  def initialize_show_completed_prefs
    session[:projects_show_completed] ||= {}
  end

  def set_project
    @project = current_user.projects.includes(:tasks).find(params[:id])
  end

  def project_params
    params.require(:project).permit(:title, :description, :due_date, :default_priority, :color)
  end
end 