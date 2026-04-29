# frozen_string_literal: true

class TaskInsightsController < ApplicationController
  def index
    prepare_form_defaults
    @question = params[:question].to_s
    @answer = nil
    @tool_calls = []
    @state_events = []
    return unless params[:ask].to_s == "1"
    return if @question.blank?
    return if @available_ai_models.empty?

    current_user.update(
      ai_summary_locale: @ai_locale,
      ai_summary_model: @ai_model
    )

    result = TaskInsightsChatService.call(
      user: current_user,
      question: @question,
      locale: @ai_locale,
      model_name: @ai_model
    )

    @answer = result.answer
    @tool_calls = result.tool_calls
    @state_events = result.state_events || []
  rescue StandardError => e
    Rails.logger.warn("Task insights chat failed: #{e.message}")
    @answer = I18n.t("application.messages.error_occurred", default: "An error occurred while processing your request.")
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
