class TasksController < ApplicationController
  TASKS_PER_PAGE = 15

  before_action :initialize_show_completed_prefs
  before_action :set_task, only: [:show, :edit, :update, :destroy, :toggle, :archive, :refresh]
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
                       COALESCE(updated_at, created_at) DESC, created_at DESC"))
    else
      @tasks = @tasks.order(Arel.sql('COALESCE(updated_at, created_at) DESC, created_at DESC'))
    end
    
    @tasks = @tasks.page(params[:page]).per(TASKS_PER_PAGE)
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
    
    @project = Project.find(params[:project_id])
    @task = current_user.tasks.build(
      project_id: params[:project_id],
      priority: @project.default_priority
    )
    
    # If we have a show_completed param, update the session
    if params[:show_completed].present?
      show_completed = params[:show_completed] == 'true'
      session[:projects_show_completed][@project.id.to_s] = show_completed
    end
  end

  def create
    @task = current_user.tasks.build(task_params)

    if @task.save
      # If the task is marked as completed, call mark_as_complete!
      @task.mark_as_complete!(current_user) if @task.completed

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
      if params[:kanban]
        render json: { success: true }
      else
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
      end
    else
      if params[:kanban]
        render json: { error: @task.errors.full_messages.join(", ") }, status: :unprocessable_entity
      else
        render :edit, status: :unprocessable_entity
      end
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
    
    # Update status based on completion
    if @task.completed
      @task.update(status: @task.project.status_by_key(:complete))
    else
      @task.update(status: @task.project.status_by_key(:not_started))
    end
    
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

  def refresh
    # TODO: Consider using a separate timestamp column for manual "refresh"
    #       instead of overwriting the standard updated_at value.
    @task.touch
    
    redirect_to task_path(@task), 
                notice: 'Task refreshed successfully.'
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

  def kanban
    @projects = current_user.projects.order(:title)
    @statuses = Status.default_statuses
    @current_project = params[:project_id].present? ? current_user.projects.find(params[:project_id]) : nil
    @sort_by = params[:sort_by] || 'updated_at'
    @priority_filter = params[:priority]
    @page = (params[:page] || 1).to_i
    @per_page = 100

    respond_to do |format|
      format.html
      format.json { render json: { projects: @projects, statuses: @statuses } }
    end
  end

  def kanban_tasks
    @current_project = params[:project_id].present? ? current_user.projects.find(params[:project_id]) : nil
    @sort_by = params[:sort_by] || 'updated_at'
    @priority_filter = params[:priority]
    @updated_within_days = params[:updated_within_days]&.to_i
    @page = (params[:page] || 1).to_i
    @per_page = 100
    @show_all_completed = params[:show_all_completed] == 'true'

    Rails.logger.debug "Kanban tasks request - Project: #{@current_project&.id}, Sort: #{@sort_by}, Page: #{@page}, Show All Completed: #{@show_all_completed}, Priority: #{@priority_filter}, Updated Within Days: #{@updated_within_days}"

    tasks = current_user.tasks
      .includes(:project, :status, :user)
      .where(archived: false)
      .order(@sort_by => :desc)

    if @current_project
      tasks = tasks.where(project: @current_project)
    end

    if @priority_filter.present?
      tasks = tasks.where(priority: @priority_filter)
    end

    if @updated_within_days.present? && @updated_within_days != 0
      if @updated_within_days > 0
        # Updated within X days
        tasks = tasks.where('tasks.updated_at >= ?', @updated_within_days.days.ago)
      else
        # Not updated within X days (negative value)
        days_ago = @updated_within_days.abs.days.ago
        tasks = tasks.where('tasks.updated_at < ?', days_ago)
      end
    end

    # Group tasks by status
    @tasks_by_status = {}
    has_more = false
    Status.default_statuses.each do |key, name|
      next if name == 'Closed' # Skip Closed status as it's included in Complete column
      
      status_tasks = tasks.where(status: { name: name })
      
      # For completed tasks, only show those from the last 7 days unless show_all_completed is true
      if key == :complete
        status_tasks = status_tasks.or(tasks.where(status: { name: 'Closed' }))
        unless @show_all_completed
          status_tasks = status_tasks.where('tasks.updated_at >= ?', 7.days.ago)
        end
      end
      
      paginated_tasks = status_tasks.page(@page).per(@per_page)
      @tasks_by_status[key] = paginated_tasks
      has_more ||= paginated_tasks.total_pages > @page
      Rails.logger.debug "Status #{key}: #{@tasks_by_status[key].count} tasks"
    end

    respond_to do |format|
      format.json { 
        render json: {
          tasks: @tasks_by_status.transform_values { |tasks| 
            tasks.map { |task| 
              {
                id: task.id,
                title: task.title,
                description: task.description,
                status: task.status.name,
                project: task.project.title,
                project_color: task.project.color,
                user: task.user.name,
                updated_at: task.updated_at,
                priority: task.priority
              }
            }
          },
          has_more: has_more
        }
      }
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
    if params[:kanban]
      render json: { error: 'Task not found or already archived.' }, status: :not_found
    else
      redirect_to tasks_path(show_completed: session[:tasks_show_completed] || false), 
                  alert: 'Task not found or already archived.'
    end
  end

  def load_projects_and_tags
    @projects = current_user.projects
    @tags = Tag.all
  end

  def task_params
    params.require(:task).permit(:title, :description, :completed, :due_date, 
                               :priority, :project_id, :status_id, :status_name, tag_ids: [])
  end
end 