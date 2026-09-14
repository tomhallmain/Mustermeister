class StatusesController < ApplicationController
  before_action :set_project, only: [:new, :create]
  before_action :set_status, only: [:edit, :update, :destroy, :move_up, :move_down]
  before_action :forbid_default_modification, only: [:edit, :update, :destroy]

  def new
    @status = @project.statuses.build
  end

  def create
    @status = @project.statuses.build(status_params)

    if @status.save
      bump_project_activity(@project)
      redirect_to edit_project_path(@project), notice: t('views.projects.edit.statuses.created')
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @status.update(status_params)
      bump_project_activity(@status.project)
      redirect_to edit_project_path(@status.project), notice: t('views.projects.edit.statuses.updated')
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    project = @status.project

    if @status.in_use?
      redirect_to edit_project_path(project), alert: t('views.projects.edit.statuses.in_use')
    else
      @status.destroy
      bump_project_activity(project)
      redirect_to edit_project_path(project), notice: t('views.projects.edit.statuses.deleted')
    end
  end

  def move_up
    project = @status.project
    bump_project_activity(project) if @status.move_earlier
    redirect_to edit_project_path(project)
  end

  def move_down
    project = @status.project
    bump_project_activity(project) if @status.move_later
    redirect_to edit_project_path(project)
  end

  private

  # Mirrors Task#update_project_activity: a status change is activity on a
  # related child record, not a direct edit of the project's own columns, so
  # it should bump last_activity_at (the projects index's actual sort key)
  # the same lightweight way task activity does, rather than updated_at
  # (which the index's default sort doesn't consult at all).
  def bump_project_activity(project)
    project.update_column(:last_activity_at, Time.current)
  end

  # Statuses are project configuration, so both finders are scoped to projects
  # the user manages rather than merely collaborates on.
  def set_project
    @project = current_user.manageable_projects.find(params[:project_id])
  end

  def set_status
    @status = Status.where(project: current_user.manageable_projects).find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to root_path, alert: t('views.projects.edit.statuses.not_found')
  end

  def forbid_default_modification
    return unless @status&.default?

    redirect_to edit_project_path(@status.project), alert: t('views.projects.edit.statuses.default_immutable')
  end

  def status_params
    params.require(:status).permit(:name)
  end
end
