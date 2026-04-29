# frozen_string_literal: true

class TaskInsightsController < ApplicationController
  def index
    prepare_form_defaults
    @question = params[:question].to_s
  end

  def create
    prepare_form_defaults
    question = params[:question].to_s.strip

    if question.blank?
      return render json: { error: "Question is required." }, status: :unprocessable_entity
    end
    if @available_ai_models.empty?
      return render json: { error: "No local Ollama models available." }, status: :unprocessable_entity
    end

    unless current_user.update(
      ai_summary_locale: @ai_locale,
      ai_summary_model: @ai_model
    )
      return render json: { error: current_user.errors.full_messages.join(", ") }, status: :unprocessable_entity
    end

    run_id = SecureRandom.uuid
    TaskInsightsRunStore.init(run_id, user_id: current_user.id)
    TaskInsightsRunJob.perform_later(run_id, current_user.id, question, @ai_locale.to_s, @ai_model.to_s)

    render json: { run_id: run_id }, status: :accepted
  end

  def status
    payload = TaskInsightsRunStore.read(params[:run_id].to_s)
    if payload.blank? || payload["user_id"].to_i != current_user.id
      head :not_found
      return
    end

    render json: payload.slice("status", "state_events", "answer", "tool_calls", "error")
  end

  private

  def prepare_form_defaults
    @available_ai_locales = I18n.available_locales.map(&:to_s)
    @available_ai_models = OllamaLlmService.available_models

    requested_ai_locale = params[:ai_locale].to_s
    @ai_locale = if @available_ai_locales.include?(requested_ai_locale)
      requested_ai_locale
    elsif current_user.ai_summary_locale.present? && @available_ai_locales.include?(current_user.ai_summary_locale)
      current_user.ai_summary_locale
    else
      I18n.locale.to_s
    end

    requested_ai_model = params[:ai_model].to_s
    preferred_model = current_user.ai_summary_model.to_s
    @ai_model = if @available_ai_models.include?(requested_ai_model)
      requested_ai_model
    elsif @available_ai_models.include?(preferred_model)
      preferred_model
    elsif @available_ai_models.include?(ENV["OLLAMA_REPORT_MODEL"].to_s)
      ENV["OLLAMA_REPORT_MODEL"].to_s
    else
      @available_ai_models.first
    end
  end
end
