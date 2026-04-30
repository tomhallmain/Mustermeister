# frozen_string_literal: true

class TaskInsightsRunJob < ApplicationJob
  queue_as :default

  def perform(run_id, user_id, question, locale, model_name, excluded_project_ids = [], conversation_id = nil)
    user = User.find(user_id)
    progress = TaskInsightsRunProgress.new(run_id)
    conversation = conversation_id.present? ? user.task_insights_conversations.find_by(id: conversation_id) : nil
    transcript_messages = []
    if conversation
      transcript_messages = conversation.task_insights_messages
        .where(role: %w[user assistant])
        .order(:created_at)
        .last(20)
        .map { |m| { role: m.role, content: m.content.to_s } }
    end

    result = TaskInsightsChatService.call(
      user: user,
      question: question,
      locale: locale.presence || I18n.default_locale,
      model_name: model_name.presence,
      excluded_project_ids: excluded_project_ids,
      transcript_messages: transcript_messages,
      progress: progress
    )

    if conversation
      conversation.task_insights_messages.create!(
        role: "assistant",
        content: result.answer.to_s,
        tool_calls: result.tool_calls || [],
        state_events: result.state_events || []
      )
      conversation.update!(last_message_at: Time.current)
    end

    TaskInsightsRunStore.complete!(run_id, result)
  rescue ActiveRecord::RecordNotFound => e
    TaskInsightsRunStore.fail!(run_id, error: e.message)
  rescue StandardError => e
    Rails.logger.warn("TaskInsightsRunJob #{run_id}: #{e.class}: #{e.message}")
    TaskInsightsRunStore.fail!(run_id, error: e.message)
  end
end
