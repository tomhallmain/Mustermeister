# frozen_string_literal: true

class TaskInsightsMessage < ApplicationRecord
  belongs_to :task_insights_conversation

  validates :role, inclusion: { in: %w[user assistant] }
  validates :content, presence: true
end
