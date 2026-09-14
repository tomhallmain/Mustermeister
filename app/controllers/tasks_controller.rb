class TasksController < ApplicationController
  TASKS_PER_PAGE = 15

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
  before_action :set_task, only: [:show, :edit, :update, :destroy, :toggle, :archive, :refresh, :translate]
  before_action :load_projects_and_tags, only: [:new, :edit, :create, :update]
  before_action :run_recurring_task_generation_check, only: [:index]

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
    @tasks = current_user.accessible_tasks.not_archived.includes(:project, :tags, :task_category, :comments)
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

    # The most recent task this user wrote and can still see. Keyed on
    # created_by, not user_id: user_id names whoever the task is assigned to,
    # so project access alone would offer up a colleague's task under a
    # "duplicate *your* last task" button.
    @last_created_task = current_user.accessible_tasks
                                     .where(created_by: current_user.id)
                                     .order(created_at: :desc)
                                     .first
  end

  def show
    @comment = Comment.new
    @comments = @task.comments.includes(:user)
    @attachments = @task.attachments.includes(:user).order(created_at: :desc)
    # Cheap defaults for the Translate confirm modal - deliberately no live
    # Ollama call here (unlike Reports/Task Insights' pages, which do call
    # OllamaLlmService.available_models synchronously on every render): the
    # modal's model suggestions are instead fetched client-side, on demand,
    # only when the user actually opens it (see translate_controller.js),
    # so viewing a task is never slowed down by Ollama being slow/unreachable.
    @translate_target_language_preview = resolve_translation_target_language
    @translate_default_model_preview = current_user.ai_summary_model.presence || ENV["OLLAMA_REPORT_MODEL"].presence
  end

  def new
    if params[:project_id].blank?
      redirect_to projects_path, notice: 'Please select a project to create a task.'
      return
    end
    
    @project = Project.find(params[:project_id])
    @task = current_user.tasks.build(
      project_id: params[:project_id],
      priority: @project.default_priority,
      task_category_id: @project.default_category_id || TaskCategory.fallback_category&.id
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
                notice: t('views.tasks.index.deleted')
    else
      @task.destroy
      redirect_to tasks_path(show_completed: session[:tasks_show_completed] || false),
                notice: t('views.tasks.index.deleted')
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
    visible_tasks = current_user.accessible_tasks
    @archived_tasks = visible_tasks.archived.includes(:user, :project)
                         .order(archived_at: :desc)
                         .page(params[:page])

    @archive_stats = {
      total_archived: visible_tasks.archived.count,
      archived_this_month: visible_tasks.archived.where('archived_at > ?', 1.month.ago).count,
      total_completed: visible_tasks.completed.count
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

  def translate
    target_language = resolve_translation_target_language

    # params[:model] is trusted as-is (the confirm modal's model field
    # accepts free text, not just models Ollama already knows about - see
    # shared/_llm_model_field) and takes priority; resolve_translation_model
    # (which does call OllamaLlmService.available_models) is only a fallback
    # for when it's blank, e.g. JS-disabled or a direct API call.
    model_name = params[:model].to_s.strip.presence || resolve_translation_model
    if model_name.blank?
      render json: { error: t('views.tasks.show.translate.no_model_available') }, status: :unprocessable_entity
      return
    end

    # Persisted the same way Reports/Task Insights persist their model
    # choice, so "the last configured model" (used to pre-fill this same
    # modal next time, and as the fallback in resolve_translation_model)
    # actually reflects what was just used here too.
    current_user.update(ai_summary_model: model_name)

    translation = TaskTranslationService.call(task: @task, target_language: target_language, model_name: model_name)
    render json: translation
  rescue TaskTranslationService::TranslationError => e
    render json: { error: e.message }, status: :unprocessable_entity
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
    @tasks = current_user.accessible_tasks
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

  def merge_tasks
    @mergeable_tasks = current_user.tasks.not_archived.includes(:project).order(:title)
  end

  def merge_tasks_execute
    target = current_user.tasks.not_archived.find_by(id: params[:target_id])
    source = current_user.tasks.not_archived.find_by(id: params[:source_id])

    if target.nil? || source.nil?
      redirect_to merge_tasks_path, alert: t('views.tasks.merge.invalid_selection')
      return
    end

    TaskMergeService.call(target: target, source: source, current_user: current_user)
    redirect_to task_path(target), notice: t('views.tasks.merge.success', target_title: target.title)
  rescue TaskMergeService::Error => e
    redirect_to merge_tasks_path, alert: t('views.tasks.merge.failure', message: e.message)
  end

  def kanban
    @projects = current_user.accessible_projects.order(:title)
    @statuses = Status.default_statuses
    @current_project = params[:project_id].present? ? current_user.projects.find(params[:project_id]) : nil
    # Only when a single project is selected AND it has a status beyond the
    # fixed default set does the board switch from the standard 5 columns to
    # one column per that project's actual (ordered) status list - see
    # kanban.html.erb/kanban.js. @custom_status_project_ids lets the project
    # filter dropdown know, without a round trip, whether switching to a
    # given project requires a full page reload to pick up different columns.
    @dynamic_project_statuses = @current_project.statuses.ordered if @current_project&.custom_statuses?
    @custom_status_project_ids = current_user.projects.joins(:statuses).merge(Status.custom).distinct.pluck(:id)
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
    @search = params[:search].presence

    AppDebugLogger.debug { "Kanban tasks request - Project: #{@current_project&.id}, Sort: #{@sort_by}, Page: #{@page}, Show All Completed: #{@show_all_completed}, Priority: #{@priority_filter}, Updated Within Days: #{@updated_within_days}, Search: #{@search}" }

    tasks = current_user.accessible_tasks
      .includes(:project, :status, :user, :task_category)
      .where(archived: false)

    tasks = case @sort_by
    when 'priority'
      # priority is a plain string column ('low'/'medium'/'high'/'leisure'), so a
      # normal order-by would sort alphabetically instead of by severity.
      tasks.order(Arel.sql("#{Task::PRIORITY_WEIGHT_SQL} DESC"))
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

    if @search.present?
      # Qualified column names are required here: kanban_tasks always builds
      # this relation with includes(:project, :status, :user, :task_category),
      # and the per-status .where(status: { name: ... }) filters below force
      # Rails to resolve ALL of those includes as SQL JOINs rather than
      # separate preload queries - projects has its own "title" column, so an
      # unqualified "title" is ambiguous once that join is in play.
      #
      # Regex (not ILIKE) so the match is anchored to a word boundary - \y is
      # Postgres's word-boundary escape - so "quart" matches "Quarterly
      # Report" and "Q1-Quarterly" but not "Requarterly". ILIKE '%term%' has
      # no such concept and would match anywhere mid-word.
      escaped_search = Regexp.escape(@search)
      tasks = tasks.where("tasks.title ~* ? OR tasks.description ~* ?", "\\y#{escaped_search}", "\\y#{escaped_search}")
    end

    if @current_project&.custom_statuses?
      render_dynamic_kanban_tasks(tasks)
    else
      render_default_kanban_tasks(tasks)
    end
  end

  private

  # Same fallback chain as ReportsController/TaskInsightsController's model
  # resolution (minus the "requested via param" tier - translate has no
  # per-request model picker, it always uses "the last configured model").
  def resolve_translation_model
    available_models = OllamaLlmService.available_models
    preferred_model = current_user.ai_summary_model.to_s
    return preferred_model if available_models.include?(preferred_model)

    env_default_model = ENV["OLLAMA_REPORT_MODEL"].to_s
    return env_default_model if available_models.include?(env_default_model)

    available_models.first
  end

  # Reuses ReportLlmSummaryService's locale -> LLM-friendly English language
  # name mapping rather than duplicating one, for whichever locale this
  # request is actually rendering in (see ApplicationController#set_locale).
  def default_translation_language
    ReportLlmSummaryService::PROMPT_COPY[I18n.locale.to_s]&.dig(:language_name) || "English"
  end

  # No configured preference isn't an error - someone would only be
  # translating a task because it isn't already in a language they want, so
  # falling back to the app's own current language is a reasonable default
  # rather than a dead end (see the Translate button's tooltip).
  def resolve_translation_target_language
    current_user.translate_target_language.presence || default_translation_language
  end

  # The standard, project-agnostic 5-column board (folds Investigated into To
  # Investigate, and Closed into Complete by name) - unchanged from before
  # custom statuses existed.
  def render_default_kanban_tasks(tasks)
    tasks_by_status = {}
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
      tasks_by_status[key] = paginated_tasks
      has_more ||= paginated_tasks.total_pages > @page
      AppDebugLogger.debug { "Status #{key}: #{tasks_by_status[key].count} tasks" }
    end

    respond_to do |format|
      format.json {
        render json: {
          dynamic: false,
          tasks: tasks_by_status.transform_values { |group| serialize_kanban_tasks(group) },
          has_more: has_more
        }
      }
    end
  end

  # One column per the current project's actual statuses (default + custom),
  # in position order, keyed by status id rather than by name/key - only used
  # once a single project with a custom status is selected (see #kanban).
  def render_dynamic_kanban_tasks(tasks)
    statuses = @current_project.statuses.ordered.to_a
    terminal_names = Status.default_statuses.values_at(:complete, :closed)

    tasks_by_status = {}
    has_more = false

    statuses.each do |status|
      status_tasks = tasks.where(status_id: status.id)

      if terminal_names.include?(status.name) && !@show_all_completed
        status_tasks = status_tasks.where('tasks.updated_at >= ?', 7.days.ago)
      end

      paginated_tasks = status_tasks.page(@page).per(@per_page)
      tasks_by_status[status.id.to_s] = paginated_tasks
      has_more ||= paginated_tasks.total_pages > @page
    end

    respond_to do |format|
      format.json {
        render json: {
          dynamic: true,
          columns: statuses.map { |s| { key: s.id.to_s, label: Task.localized_status_name(s), terminal: terminal_names.include?(s.name) } },
          tasks: tasks_by_status.transform_values { |group| serialize_kanban_tasks(group) },
          has_more: has_more
        }
      }
    end
  end

  def serialize_kanban_tasks(tasks)
    tasks.map do |task|
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
    end
  end

  def initialize_show_completed_prefs
    session[:projects_show_completed] ||= {}
    session[:tasks_show_completed] = false if session[:tasks_show_completed].nil?
  end

  def run_recurring_task_generation_check
    RecurringTaskGenerationCheck.run_if_due!
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
    @task = current_user.accessible_tasks.not_archived.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    if params[:kanban]
      render json: { error: 'Task not found or already archived.' }, status: :not_found
    else
      redirect_to tasks_path(show_completed: session[:tasks_show_completed] || false), 
                  alert: 'Task not found or already archived.'
    end
  end

  def load_projects_and_tags
    @projects = current_user.accessible_projects.order(:title)
    @tags = Tag.all
    TaskCategory.ensure_default_categories!
    @task_categories = TaskCategory.default_categories.order(:name) + current_user.task_categories.order(:name)
  end

  # Pre-fills a freshly built task with another task's field values, for the
  # "duplicate this task" flow. Intentionally excludes completed/status so the
  # copy always starts fresh, and only ever copies from a task the current
  # user owns.
  def copy_fields_from_source_task!(task)
    source_task = current_user.accessible_tasks.find_by(id: params[:source_task_id])
    return unless source_task

    task.assign_attributes(
      title: "#{source_task.title} #{t('views.tasks.form.copy_suffix')}",
      description: source_task.description,
      priority: source_task.priority,
      due_date: source_task.due_date,
      task_category_id: source_task.task_category_id,
      estimated_minutes: source_task.estimated_minutes,
      tag_ids: source_task.tag_ids
    )
  end

  def task_params
    params.require(:task).permit(:title, :description, :completed, :due_date,
                               :priority, :project_id, :status_id, :status_name, :task_category_id,
                               :estimated_minutes, :scheduled_at, :user_id, :confirm_duplicate, tag_ids: [])
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