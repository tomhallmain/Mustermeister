class TasksController < ApplicationController
  TASKS_PER_PAGE = 15

  before_action :initialize_show_completed_prefs
  before_action :set_task, only: [:show, :edit, :update, :destroy, :toggle, :archive]
  before_action :load_projects_and_tags, only: [:new, :edit, :create, :update]

  def index
    # Add headers to disable Turbo for this response to prevent double requests
    response.headers["Turbo-Frame"] = "_top"
    
    # If show_completed param is present, update the session preference
    if params[:show_completed].present?
      show_completed = params[:show_completed] == 'true'
      session[:tasks_show_completed] = show_completed
    end
    
    # Get the current stored preference (default to false if nil)
    stored_preference = session[:tasks_show_completed]
    stored_preference = false if stored_preference.nil?
    
    # If no param and we have a stored preference, redirect to include it
    if params[:show_completed].nil?
      redirect_to tasks_path(show_completed: stored_preference, page: params[:page])
      return
    end
    
    # Current preference is from params (already stored in session above)
    current_preference = params[:show_completed] == 'true'
    
    # Now load the tasks based on the current preference
    @tasks = current_user.tasks.not_archived.includes(:project, :tags)
    @tasks = @tasks.not_completed unless current_preference
    @tasks = @tasks.order(Arel.sql('COALESCE(updated_at, created_at) DESC, created_at DESC'))
                   .page(params[:page]).per(TASKS_PER_PAGE)
  end

  def show
    @comment = Comment.new
    @comments = @task.comments.includes(:user)
  end

  def new
    if params[:project_id].blank?
      redirect_to projects_path, notice: 'Please select a project to create a task.'
      return
    end
    
    project = Project.find(params[:project_id])
    @task = current_user.tasks.build(
      project_id: params[:project_id],
      priority: project.default_priority
    )
    
    # If we have a show_completed param, update the session
    if params[:show_completed].present?
      show_completed = params[:show_completed] == 'true'
      session[:projects_show_completed][project.id.to_s] = show_completed
    end
  end

  def create
    @task = current_user.tasks.build(task_params)

    if @task.save
      if @task.project
        show_completed = session[:projects_show_completed][@task.project.id.to_s]
        # Default to false if not set in session
        show_completed = show_completed.nil? ? false : show_completed
        redirect_to project_path(@task.project, show_completed: show_completed), 
                    notice: 'Task was successfully created.'
      else
        redirect_to tasks_path(show_completed: session[:tasks_show_completed] || false), 
                    notice: 'Task was successfully created.'
      end
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @task.update(task_params)
      if @task.project
        show_completed = session[:projects_show_completed][@task.project.id.to_s]
        # Default to false if not set in session
        show_completed = show_completed.nil? ? false : show_completed
        redirect_to project_path(@task.project, show_completed: show_completed), 
                    notice: 'Task was successfully updated.'
      else
        redirect_to tasks_path(show_completed: session[:tasks_show_completed] || false), 
                    notice: 'Task was successfully updated.'
      end
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    project = @task.project
    
    if project
      project_id = project.id.to_s
      show_completed = session[:projects_show_completed][project_id]
      # Default to false if not set in session
      show_completed = show_completed.nil? ? false : show_completed
      
      @task.destroy
      redirect_to project_path(project, show_completed: show_completed), 
                notice: 'Task was successfully deleted.'
    else
      @task.destroy
      redirect_to tasks_path(show_completed: session[:tasks_show_completed] || false), 
                notice: 'Task was successfully deleted.'
    end
  end

  def toggle
    @task.update(completed: !@task.completed)
    
    # If show_completed param is present, use it for the redirect
    show_completed = if params[:show_completed].present?
                       params[:show_completed]
                     else
                       session[:tasks_show_completed] || false
                     end
    
    redirect_back(fallback_location: tasks_path(show_completed: show_completed), 
                  notice: 'Task status updated.')
  end

  def archive_index
    @archived_tasks = Task.archived.includes(:user, :project)
                         .order(archived_at: :desc)
                         .page(params[:page])
    
    @archive_stats = {
      total_archived: Task.archived.count,
      archived_this_month: Task.archived.where('archived_at > ?', 1.month.ago).count,
      total_completed: Task.completed.count
    }
  end

  def archive
    # If show_completed param is present, use it for the redirect
    show_completed = if params[:show_completed].present?
                       params[:show_completed]
                     else
                       session[:tasks_show_completed] || false
                     end
    
    if @task.archive!(current_user)
      redirect_to tasks_path(show_completed: show_completed), 
                notice: 'Task was successfully archived.'
    else
      redirect_to @task, alert: @task.errors.full_messages.join(", ")
    end
  end

  def bulk_archive
    before_date = params[:before_date].presence || 6.months.ago
    
    begin
      count = TaskManagementService.archive_completed_tasks(
        before_date: before_date,
        current_user: current_user
      )
      
      redirect_to archives_path, 
                  notice: "Successfully archived #{count} completed tasks."
    rescue TaskManagementService::Error => e
      redirect_to tasks_path(show_completed: session[:tasks_show_completed] || false), 
                  alert: "Failed to archive tasks: #{e.message}"
    end
  end

  def reschedule_index
    @tasks = current_user.tasks
                        .not_archived
                        .includes(:project, :tags)
                        .order(due_date: :asc)
                        .page(params[:page])
    
    @reschedule_stats = {
      total_tasks: @tasks.count,
      overdue_tasks: @tasks.overdue.count,
      upcoming_tasks: @tasks.where('due_date > ?', Time.current).count
    }
  end

  def bulk_reschedule
    begin
      count = TaskManagementService.bulk_reschedule(
        task_ids: params[:task_ids],
        new_due_date: params[:new_due_date],
        current_user: current_user
      )
      
      redirect_to tasks_path(show_completed: session[:tasks_show_completed] || false), 
                  notice: "Successfully rescheduled #{count} tasks."
    rescue TaskManagementService::Error => e
      redirect_to reschedule_path, 
                  alert: "Failed to reschedule tasks: #{e.message}"
    end
  end

  private

  def initialize_show_completed_prefs
    session[:projects_show_completed] ||= {}
    session[:tasks_show_completed] = false if session[:tasks_show_completed].nil?
  end

  def set_task
    @task = Task.not_archived.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to tasks_path(show_completed: session[:tasks_show_completed] || false), 
                alert: 'Task not found or already archived.'
  end

  def load_projects_and_tags
    @projects = current_user.projects
    @tags = Tag.all
  end

  def task_params
    params.require(:task).permit(:title, :description, :completed, :due_date, 
                               :priority, :project_id, tag_ids: [])
  end
end 