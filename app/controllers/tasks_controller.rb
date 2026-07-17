class TasksController < ApplicationController
  TASKS_PER_PAGE = 15
  PRIORITY_RANK_SQL = "CASE tasks.priority WHEN 'high' THEN 4 WHEN 'medium' THEN 3 WHEN 'low' THEN 2 ELSE 1 END DESC"

  TASK_INDEX_DEFAULT_SORT = 'updated_desc'
  # Active (not completed) tasks oldest-first, then completed tasks newest-first -
  # deliberately the reverse of the kanban board's "most recently active first" logic,
  # surfacing neglected active tasks while keeping a normal recency log of completed ones.
  TASK_INDEX_ACTIVE_OLDEST_SORT = 'active_oldest_completed_newest'
  TASK_INDEX_SORT_OPTIONS = [TASK_INDEX_DEFAULT_SORT, TASK_INDEX_ACTIVE_OLDEST_SORT].freeze

  ACTIVE_OLDEST_COMPLETED_NEWEST_SQL = <<~SQL.squish
    CASE WHEN tasks.completed THEN 1 ELSE 0 END ASC,
    CASE WHEN tasks.completed
      THEN -EXTRACT(EPOCH FROM COALESCE(tasks.updated_at, tasks.created_at))
      ELSE EXTRACT(EPOCH FROM COALESCE(tasks.updated_at, tasks.created_at))
    END ASC
  SQL

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
    @tasks = current_user.tasks.not_archived.includes(:project, :tags, :task_category)
    @tasks = @tasks.not_completed unless current_preference

    # Remember sort_by/search whenever explicitly provided, and fall back to the
    # remembered value - without forcing a redirect the way show_completed does,
    # so a bare tasks_path(show_completed: ...) call still resolves directly.
    if params[:sort_by].present?
      session[:tasks_sort_by] = params[:sort_by]
    end
    requested_sort_by = params[:sort_by].presence || session[:tasks_sort_by] || TASK_INDEX_DEFAULT_SORT
    @sort_by = TASK_INDEX_SORT_OPTIONS.include?(requested_sort_by) ? requested_sort_by : TASK_INDEX_DEFAULT_SORT
    sort_sql = task_index_sort_sql(@sort_by)

    # search has no meaningful "default" - remember it (including an explicit
    # clear) whenever the key is present at all, distinct from it being absent.
    if params.key?(:search)
      session[:tasks_search] = params[:search].presence
    end
    @search = params.key?(:search) ? params[:search] : session[:tasks_search]

    if @search.present?
      search_term = @search
      @tasks = @tasks.where("title ILIKE ? OR description ILIKE ?",
                           "%#{search_term}%",
                           "%#{search_term}%")
                     .order(Arel.sql("
                       CASE
                         WHEN title ILIKE '#{search_term}%' THEN 1
                         WHEN title ILIKE '% #{search_term}%' THEN 2
                         ELSE 3
                       END,
                       #{sort_sql}"))
    else
      @tasks = @tasks.order(Arel.sql(sort_sql))
    end

    @tasks = @tasks.page(params[:page]).per(TASKS_PER_PAGE)

    @last_created_task = current_user.tasks.order(created_at: :desc).first
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

    if params[:source_task_id].present?
      copy_fields_from_source_task!(@task)
    end

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
    updated = false

    Task.transaction do
      updated = @task.update(task_params)
      next unless updated

      apply_task_result_for_completion!(@task)
      raise ActiveRecord::Rollback if @task.errors.any?
    end

    if updated && @task.errors.empty?

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
    toggled = false

    Task.transaction do
      toggled = @task.update(completed: !@task.completed)
      raise ActiveRecord::Rollback unless toggled

      if @task.completed
        @task.update!(status: @task.project.status_by_key(:complete))
        apply_task_result_for_completion!(@task)
      else
        @task.update!(status: @task.project.status_by_key(:not_started))
      end

      raise ActiveRecord::Rollback if @task.errors.any?
    end

    @task.reload

    if !toggled || @task.errors.any?
      redirect_back(
        fallback_location: tasks_path(show_completed: session[:tasks_show_completed] || false),
        alert: @task.errors.full_messages.join(", ")
      )
      return
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
      .includes(:project, :status, :user, :task_category)
      .where(archived: false)

    tasks = case @sort_by
    when 'priority'
      # priority is a plain string column ('low'/'medium'/'high'/'leisure'), so a
      # normal order-by would sort alphabetically instead of by severity.
      tasks.order(Arel.sql(PRIORITY_RANK_SQL))
    when 'updated_at_asc'
      tasks.order(updated_at: :asc)
    else
      tasks.order(@sort_by => :desc)
    end

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
                priority: task.priority,
                category: task.task_category&.display_name,
                category_color: task.task_category&.color
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

  def task_index_sort_sql(sort_by)
    case sort_by
    when TASK_INDEX_ACTIVE_OLDEST_SORT
      ACTIVE_OLDEST_COMPLETED_NEWEST_SQL
    else
      'COALESCE(updated_at, created_at) DESC, created_at DESC'
    end
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
    TaskCategory.ensure_default_categories!
    @task_categories = TaskCategory.default_categories.order(:name) + current_user.task_categories.order(:name)
  end

  # Pre-fills a freshly built task with another task's field values, for the
  # "duplicate this task" flow. Intentionally excludes completed/status so the
  # copy always starts fresh, and only ever copies from a task the current
  # user owns.
  def copy_fields_from_source_task!(task)
    source_task = current_user.tasks.find_by(id: params[:source_task_id])
    return unless source_task

    task.assign_attributes(
      title: "#{source_task.title} #{t('views.tasks.form.copy_suffix')}",
      description: source_task.description,
      priority: source_task.priority,
      due_date: source_task.due_date,
      task_category_id: source_task.task_category_id,
      tag_ids: source_task.tag_ids
    )
  end

  def task_params
    params.require(:task).permit(:title, :description, :completed, :due_date,
                               :priority, :project_id, :status_id, :status_name, :task_category_id, tag_ids: [])
  end

  def task_result_params
    params.fetch(:task_result, {}).permit(:result, :result_reason)
  end

  def apply_task_result_for_completion!(task)
    return unless task.completed?

    payload = task_result_params.to_h
    payload["result"] = "complete" if payload["result"].blank?
    payload["result_reason"] = nil unless payload["result"] == "incomplete"

    result_record = task.task_result || task.build_task_result
    result_record.assign_attributes(payload)

    return if result_record.save

    task.errors.add(:base, result_record.errors.full_messages.join(", "))
  end
end 