class ProjectsController < ApplicationController
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
    @tasks = @project.tasks.includes(:tags, :user)
                    .order(created_at: :desc)
                    .page(params[:page]).per(15)
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

  def set_project
    @project = current_user.projects.includes(:tasks).find(params[:id])
  end

  def project_params
    params.require(:project).permit(:title, :description, :due_date)
  end
end 