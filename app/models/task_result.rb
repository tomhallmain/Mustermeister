class TaskResult < ApplicationRecord
  belongs_to :task

  enum :result, { complete: 0, incomplete: 1 }, prefix: true

  validates :result, presence: true
  validates :result_reason, presence: true, if: :result_incomplete?
  validates :result_reason, absence: true, unless: :result_incomplete?

  REASON_SUGGESTION_KEYS = %w[
    unneeded
    too_challenging
    blocked
    out_of_scope
    waiting_on_input
  ].freeze
end
