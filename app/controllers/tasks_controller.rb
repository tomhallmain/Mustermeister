class TasksController < ApplicationController
  before_action :set_task, only: [:show, :edit, :update, :destroy, :toggle, :archive]
  before_action :load_projects_and_tags, only: [:new, :edit, :create, :update]

  def index
    @tasks = current_user.tasks.not_archived.includes(:project, :tags)
    @tasks = @tasks.not_completed unless params[:show_completed]
    @tasks = @tasks.order(created_at: :desc)
                   .page(params[:page]).per(15)
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
    @task = current_user.tasks.build(project_id: params[:project_id])
  end

  def create
    @task = current_user.tasks.build(task_params)

    if @task.save
      redirect_to @task.project ? project_path(@task.project) : tasks_path, 
                  notice: 'Task was successfully created.'
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @task.update(task_params)
      redirect_to @task.project ? project_path(@task.project) : tasks_path, 
                  notice: 'Task was successfully updated.'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    project = @task.project
    @task.destroy
    redirect_to project ? project_path(project) : tasks_path, 
                notice: 'Task was successfully deleted.'
  end

  def toggle
    @task.update(completed: !@task.completed)
    redirect_back_or_to tasks_path, notice: 'Task status updated.'
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
    if @task.archive!(current_user)
      redirect_to tasks_path, notice: 'Task was successfully archived.'
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
      redirect_to tasks_path, 
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
      
      redirect_to tasks_path, 
                  notice: "Successfully rescheduled #{count} tasks."
    rescue TaskManagementService::Error => e
      redirect_to reschedule_path, 
                  alert: "Failed to reschedule tasks: #{e.message}"
    end
  end

  private

  def set_task
    @task = Task.not_archived.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to tasks_path, alert: 'Task not found or already archived.'
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