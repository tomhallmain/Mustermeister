class TaskCategoriesController < ApplicationController
  before_action :set_task_category, only: [:edit, :update, :destroy]

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
    @task_category = current_user.task_categories.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to task_categories_path, alert: "Task category not found."
  end

  def task_category_params
    params.require(:task_category).permit(:name)
  end
end
