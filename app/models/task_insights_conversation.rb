# frozen_string_literal: true

class TaskInsightsConversation < ApplicationRecord
  belongs_to :user
  has_many :task_insights_messages, dependent: :destroy

  validates :title, presence: true
end
