# frozen_string_literal: true

class TaskInsightsController < ApplicationController
  helper ApplicationHelper

  def index
    prepare_form_defaults
    @question = params[:question].to_s
    @conversations = current_user.task_insights_conversations.order(last_message_at: :desc).limit(30)
    @active_conversation = if params[:conversation_id].present?
      @conversations.find { |c| c.id == params[:conversation_id].to_i }
    else
      @conversations.first
    end
    @messages = @active_conversation ? @active_conversation.task_insights_messages.order(:created_at) : []
  end

  def create
    prepare_form_defaults
    question = params[:question].to_s.strip
    excluded_project_ids = extract_excluded_project_ids
    conversation = find_or_create_conversation(question)

    if question.blank?
      return render json: { error: "Question is required." }, status: :unprocessable_entity
    end
    if @ai_model.blank?
      return render json: { error: "No Ollama models are available." }, status: :unprocessable_entity
    end

    unless current_user.update(
      ai_summary_locale: @ai_locale,
      ai_summary_model: @ai_model,
      task_insights_excluded_project_ids: excluded_project_ids
    )
      return render json: { error: current_user.errors.full_messages.join(", ") }, status: :unprocessable_entity
    end

    run_id = SecureRandom.uuid
    TaskInsightsRunStore.init(run_id, user_id: current_user.id)
    conversation.task_insights_messages.create!(role: "user", content: question)
    conversation.update!(last_message_at: Time.current)
    TaskInsightsRunJob.perform_later(
      run_id,
      current_user.id,
      question,
      @ai_locale.to_s,
      @ai_model.to_s,
      excluded_project_ids,
      conversation.id
    )

    render json: { run_id: run_id, conversation_id: conversation.id }, status: :accepted
  end

  def status
    payload = TaskInsightsRunStore.read(params[:run_id].to_s)
    if payload.blank? || payload["user_id"].to_i != current_user.id
      head :not_found
      return
    end

    json = payload.slice("status", "state_events", "answer", "tool_calls", "error")
    if %w[complete failed].include?(json["status"]) && json["answer"].present?
      json = json.merge("answer_html" => helpers.markdown_robust(json["answer"].to_s))
    end
    render json: json
  end

  def ollama_health
    models = OllamaLlmService.available_models
    render json: { ok: models.any?, models: models }
  end

  private

  def prepare_form_defaults
    @available_ai_locales = I18n.available_locales.map(&:to_s)
    @available_ai_models = OllamaLlmService.available_models
    @available_projects = current_user.accessible_projects.order(:title)

    requested_ai_locale = params[:ai_locale].to_s
    @ai_locale = if @available_ai_locales.include?(requested_ai_locale)
      requested_ai_locale
    elsif current_user.ai_summary_locale.present? && @available_ai_locales.include?(current_user.ai_summary_locale)
      current_user.ai_summary_locale
    else
      I18n.locale.to_s
    end

    # requested_ai_model is trusted as-is (not required to already be in
    # @available_ai_models) - see the matching comment in
    # ReportsController#analysis.
    requested_ai_model = params[:ai_model].to_s.strip
    preferred_model = current_user.ai_summary_model.to_s
    @ai_model = if requested_ai_model.present?
      requested_ai_model
    elsif preferred_model.present?
      preferred_model
    elsif ENV["OLLAMA_REPORT_MODEL"].present?
      ENV["OLLAMA_REPORT_MODEL"].to_s
    else
      @available_ai_models.first
    end

    @excluded_project_ids = selected_excluded_project_ids
  end

  def extract_excluded_project_ids
    raw = params[:excluded_project_ids]
    ids = raw.is_a?(Array) ? raw : current_user.task_insights_excluded_project_ids
    allowed_ids = current_user.accessible_projects.where(id: ids).pluck(:id)
    allowed_ids.map(&:to_i)
  end

  def selected_excluded_project_ids
    extract_excluded_project_ids
  end

  def find_or_create_conversation(question)
    if params[:conversation_id].present?
      existing = current_user.task_insights_conversations.find_by(id: params[:conversation_id].to_i)
      return existing if existing
    end

    title = question.truncate(80, omission: "...")
    current_user.task_insights_conversations.create!(
      title: title,
      last_message_at: Time.current
    )
  end
end
