class TaskCategoriesController < ApplicationController
  before_action :set_task_category, only: [:edit, :update, :destroy]
  before_action :forbid_default_category_destroy, only: [:destroy]

  def index
    TaskCategory.ensure_default_categories!
    @default_categories = TaskCategory.default_categories.order(:name)
    @custom_categories = current_user.task_categories.order(:name)
  end

  def new
    @task_category = current_user.task_categories.build
  end

  def create
    @task_category = current_user.task_categories.build(task_category_params)

    if @task_category.save
      redirect_to task_categories_path, notice: "Task category was successfully created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  # Default categories are shared system-wide, so only their color can be
  # changed here (see #task_category_params) - their name stays fixed so the
  # "always available" baseline list can't be renamed out from under anyone.
  def update
    if @task_category.update(task_category_params)
      redirect_to task_categories_path, notice: "Task category was successfully updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @task_category.destroy
    redirect_to task_categories_path, notice: "Task category was successfully deleted."
  end

  private

  def set_task_category
    @task_category = TaskCategory.where(user_id: [nil, current_user.id]).find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to task_categories_path, alert: "Task category not found."
  end

  def forbid_default_category_destroy
    return unless @task_category.default?

    redirect_to task_categories_path, alert: "Default categories cannot be deleted."
  end

  def task_category_params
    permitted_attributes = @task_category&.default? ? [:color] : [:name, :color]
    params.require(:task_category).permit(*permitted_attributes)
  end
end
