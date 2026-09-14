class ProjectMembershipsController < ApplicationController
  before_action :set_project, only: :create
  before_action :set_membership, only: [:update, :destroy]

  def create
    membership = @project.project_memberships.build(create_params)

    if membership.save
      redirect_to edit_project_path(@project), notice: t('views.projects.edit.members.added')
    else
      redirect_to edit_project_path(@project), alert: membership.errors.full_messages.to_sentence
    end
  end

  def update
    if @membership.update(update_params)
      redirect_to edit_project_path(@membership.project), notice: t('views.projects.edit.members.role_updated')
    else
      redirect_to edit_project_path(@membership.project), alert: @membership.errors.full_messages.to_sentence
    end
  end

  def destroy
    project = @membership.project
    @membership.destroy

    # A manager may remove their own membership, which puts the project
    # settings page out of reach - land somewhere still visible to them.
    if project.manager?(current_user)
      redirect_to edit_project_path(project), notice: t('views.projects.edit.members.removed')
    else
      redirect_to projects_path, notice: t('views.projects.edit.members.removed')
    end
  end

  private

  # Managing who is in a project is a manager action, so both finders resolve
  # through manageable_projects and an unreachable id behaves as missing.
  def set_project
    @project = current_user.manageable_projects.find(params[:project_id])
  end

  def set_membership
    @membership = ProjectMembership.where(project: current_user.manageable_projects).find(params[:id])
  end

  def create_params
    params.require(:project_membership).permit(:user_id, :role)
  end

  # Only the role is editable; pointing an existing row at a different person
  # is an add plus a remove, not an update.
  def update_params
    params.require(:project_membership).permit(:role)
  end
end
