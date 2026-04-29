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
end
