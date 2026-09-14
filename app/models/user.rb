class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  # Target languages offered for TaskTranslationService - deliberately not
  # tied to I18n.available_locales (the app's own 4 UI locales): this is
  # "what language should my tasks be translated into", a separate concern
  # from the UI's own chrome language, so it can offer a broader set.
  TRANSLATE_LANGUAGES = [
    "Spanish", "French", "German", "Italian", "Portuguese", "Dutch",
    "Russian", "Polish", "Turkish", "Arabic", "Hindi",
    "Chinese (Simplified)", "Japanese", "Korean", "Vietnamese", "Swedish"
  ].freeze

  # "read" is the default for every user, including those migrated from the
  # older plaintext-token column: enabling write-back is always a deliberate
  # act, never something an existing token acquires on its own.
  API_TOKEN_SCOPES = %w[read read_write].freeze

  has_many :projects, dependent: :destroy
  has_many :tasks, dependent: :nullify
  has_many :comments, dependent: :nullify
  has_many :task_insights_conversations, dependent: :destroy
  has_many :task_categories, dependent: :destroy
  has_many :recurring_task_templates, dependent: :destroy
  has_many :notifications, dependent: :destroy
  has_many :project_memberships, dependent: :destroy
  has_many :member_projects, through: :project_memberships, source: :project

  validates :name, presence: true
  validates :email, presence: true, 
                   uniqueness: { case_sensitive: false },
                   format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :theme_preference, inclusion: { in: %w[day night auto], allow_blank: true }
  validates :ai_summary_locale, inclusion: { in: I18n.available_locales.map(&:to_s), allow_blank: true }
  validates :translate_target_language, inclusion: { in: TRANSLATE_LANGUAGES, allow_blank: true }
  validates :api_token_scope, inclusion: { in: API_TOKEN_SCOPES }

  # Only the SHA256 digest of an API token is stored, so a leaked database
  # dump or query log yields nothing a caller could authenticate with. The
  # raw token exists exactly once, in the response to #regenerate_api_token!.
  def self.digest_api_token(raw_token)
    Digest::SHA256.hexdigest(raw_token.to_s)
  end

  # Looked up by digest through a unique index rather than by comparing the
  # secret itself, so no comparison of the caller-supplied token against a
  # stored one happens at all and there is no byte-by-byte timing signal to
  # measure.
  def self.authenticate_api_token(raw_token)
    return nil if raw_token.blank?

    find_by(api_token_digest: digest_api_token(raw_token))
  end

  # Returns the raw token. It is unrecoverable afterwards, so a caller that
  # does not show or store it here has thrown it away.
  def regenerate_api_token!
    raw_token = SecureRandom.hex(32)
    update!(api_token_digest: self.class.digest_api_token(raw_token))
    raw_token
  end

  def api_token?
    api_token_digest.present?
  end

  def api_token_read_write?
    api_token_scope == "read_write"
  end

  # Read access to a shared project: owned outright, or joined through a
  # membership. This is what `projects` widens to wherever a controller means
  # "projects I can see" rather than "projects that are mine".
  # A subquery rather than a join plus DISTINCT: a joined-and-deduplicated
  # relation cannot be ordered by an expression that is not also selected, and
  # callers order these by computed SQL (weighted progress, last task update).
  def accessible_projects
    Project.where(user_id: id).or(Project.where(id: project_memberships.select(:project_id)))
  end

  # Configuration access: statuses, recurring templates, project settings.
  # Narrower than accessible_projects and wider than `projects`.
  def manageable_projects
    Project.where(user_id: id)
           .or(Project.where(id: project_memberships.where(role: "manager").select(:project_id)))
  end

  # Task access follows the project, not tasks.user_id - a collaborator works
  # every task in a project they are in, including ones they did not create.
  def accessible_tasks
    Task.where(project: accessible_projects)
  end

  def assigned_tasks
    tasks.where(completed: false).order(due_date: :asc)
  end

  def completed_tasks
    tasks.where(completed: true).order(updated_at: :desc)
  end
end
