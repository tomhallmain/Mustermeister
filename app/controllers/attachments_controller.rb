class AttachmentsController < ApplicationController
  before_action :set_task, only: [:create]
  before_action :set_attachment, only: [:destroy, :download]

  def create
    @attachment = @task.attachments.build(file: params.dig(:attachment, :file), user: current_user)

    if @attachment.save
      redirect_to task_path(@task), notice: t('views.attachments.created')
    else
      redirect_to task_path(@task), alert: @attachment.errors.full_messages.join(", ")
    end
  end

  def destroy
    task = @attachment.task
    @attachment.destroy
    redirect_to task_path(task), notice: t('views.attachments.deleted')
  end

  def download
    send_data @attachment.file.read,
      filename: @attachment.file.original_filename,
      type: @attachment.file.mime_type,
      disposition: "attachment"
    response.headers["X-Content-Type-Options"] = "nosniff"
  end

  private

  def set_task
    @task = current_user.tasks.not_archived.find(params[:task_id])
  end

  # Attachment#user_id is the *uploader*, not the task owner, so this scopes
  # via the attachment's task's owner instead - a bad/foreign id raises
  # RecordNotFound the same way CommentsController#destroy's
  # current_user.comments.find already does for comments.
  def set_attachment
    @attachment = Attachment.joins(:task).where(tasks: { user_id: current_user.id }).find(params[:id])
  end
end
