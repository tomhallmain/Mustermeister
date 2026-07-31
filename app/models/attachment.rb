# frozen_string_literal: true

class Attachment < ApplicationRecord
  include AttachmentUploader::Attachment(:file)

  belongs_to :task
  belongs_to :user

  validates :file, presence: true

  after_create :bump_project_activity
  after_destroy :bump_project_activity

  private

  # Comment creation doesn't actually bump last_activity_at today
  # (Task#update_project_activity only fires on Task#save) - Attachment does
  # its own direct touch so upload/delete activity is visible in the
  # projects index sort. Plain after_create/after_destroy (not the _commit
  # variants), matching Task#update_project_activity's own plain after_save -
  # _commit callbacks never fire under this suite's transactional tests
  # (each test runs in a rolled-back transaction, never a real commit).
  def bump_project_activity
    task.project.update_column(:last_activity_at, Time.current)
  end
end
