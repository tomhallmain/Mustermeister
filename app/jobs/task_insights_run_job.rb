# frozen_string_literal: true

class TaskInsightsRunJob < ApplicationJob
  queue_as :default

  def perform(run_id, user_id, question, locale, model_name, excluded_project_ids = [])
    user = User.find(user_id)
    progress = TaskInsightsRunProgress.new(run_id)

    result = TaskInsightsChatService.call(
      user: user,
      question: question,
      locale: locale.presence || I18n.default_locale,
      model_name: model_name.presence,
      excluded_project_ids: excluded_project_ids,
      progress: progress
    )

    TaskInsightsRunStore.complete!(run_id, result)
  rescue ActiveRecord::RecordNotFound => e
    TaskInsightsRunStore.fail!(run_id, error: e.message)
  rescue StandardError => e
    Rails.logger.warn("TaskInsightsRunJob #{run_id}: #{e.class}: #{e.message}")
    TaskInsightsRunStore.fail!(run_id, error: e.message)
  end
end
