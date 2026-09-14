class ProjectMembership < ApplicationRecord
  # "member" can work every task in the project; "manager" can additionally
  # configure the project and manage who else is in it. A read-only tier is
  # deliberately not part of this set yet.
  ROLES = %w[member manager].freeze

  belongs_to :project
  belongs_to :user

  validates :role, inclusion: { in: ROLES }
  validates :user_id, uniqueness: { scope: :project_id }
  validate :owner_is_not_also_a_member

  before_destroy :unassign_their_tasks
  after_create_commit :notify_new_member

  def manager?
    role == "manager"
  end

  private

  def notify_new_member
    Notification.notify!(
      user: user,
      title: I18n.t('notifications.events.added_to_project.title', project: project.title),
      body: I18n.t("notifications.events.added_to_project.body.#{role}", project: project.title),
      kind: "added_to_project",
      link_path: Rails.application.routes.url_helpers.project_path(project)
    )
  end

  # Leaving a departing member's tasks assigned to them would leave work
  # pointing at someone who can no longer open it. update_all deliberately -
  # this is a bulk bookkeeping correction, not an edit worth a version each.
  def unassign_their_tasks
    project.tasks.where(user_id: user_id).update_all(user_id: nil)
  end

  # The owner's access is derived from projects.user_id. A membership row for
  # them would be a second, independently editable source of truth for the same
  # access, which could then disagree with itself.
  def owner_is_not_also_a_member
    return if project.nil? || user_id.nil?
    return unless project.user_id == user_id

    errors.add(:user, :is_project_owner)
  end
end
