class RecurringTaskTemplatesController < ApplicationController
  before_action :run_generation_check
  before_action :set_recurring_task_template, only: [:edit, :update, :destroy, :toggle]
  before_action :load_form_collections, only: [:new, :edit, :create, :update]

  def index
    @recurring_task_templates = current_user.recurring_task_templates
      .includes(:project, :task_category)
      .order(created_at: :desc)
  end

  def new
    @recurring_task_template = current_user.recurring_task_templates.build(
      base_unit: 'month',
      interval: 1,
      start_date: Date.current
    )
  end

  def create
    @recurring_task_template = current_user.recurring_task_templates.build(recurring_task_template_params)

    if @recurring_task_template.save
      redirect_to recurring_task_templates_path, notice: t('views.recurring_task_templates.index.created')
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @recurring_task_template.update(recurring_task_template_params)
      redirect_to recurring_task_templates_path, notice: t('views.recurring_task_templates.index.updated')
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @recurring_task_template.destroy
    redirect_to recurring_task_templates_path, notice: t('views.recurring_task_templates.index.deleted')
  end

  def toggle
    @recurring_task_template.update!(active: !@recurring_task_template.active?)
    redirect_to recurring_task_templates_path
  end

  private

  def run_generation_check
    RecurringTaskGenerationCheck.run_if_due!
  end

  def set_recurring_task_template
    @recurring_task_template = current_user.recurring_task_templates.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to recurring_task_templates_path, alert: t('views.recurring_task_templates.index.not_found')
  end

  def load_form_collections
    @projects = current_user.projects.order(:title)
    @task_categories = TaskCategory.where(user_id: [nil, current_user.id]).order(:name)
  end

  def recurring_task_template_params
    params.require(:recurring_task_template).permit(
      :title, :description, :project_id, :priority, :task_category_id,
      :base_unit, :interval, :start_date, :active
    )
  end
end
