class CommentsController < ApplicationController
  def create
    @task = current_user.accessible_tasks.find(params[:task_id])
    @comment = @task.comments.build(comment_params)
    @comment.user = current_user

    if @comment.save
      redirect_to task_path(@task), notice: 'Comment was successfully added.'
    else
      redirect_to task_path(@task), alert: 'Error adding comment.'
    end
  end

  def destroy
    @comment = current_user.comments.find(params[:id])
    @task = @comment.task
    @comment.destroy
    redirect_to task_path(@task), notice: 'Comment was successfully deleted.'
  end

  private

  def comment_params
    params.require(:comment).permit(:content)
  end
end 