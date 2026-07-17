class TaskCategory < ApplicationRecord
  belongs_to :user, optional: true
  has_many :tasks, dependent: :nullify

  validates :name, presence: true, uniqueness: { scope: :user_id, case_sensitive: false }

  before_save :normalize_name

  scope :default_categories, -> { where(user_id: nil) }
  scope :custom_categories, -> { where.not(user_id: nil) }

  def self.default_category_names
    ["Feature", "Fix", "Tech Debt", "Chore", "Documentation"]
  end

  # Idempotent: safe to call from seeds, controllers, or anywhere the default
  # list needs to be guaranteed to exist (the test DB is loaded from schema.rb,
  # not replayed migrations, so a migration-only seed isn't enough).
  def self.ensure_default_categories!
    default_category_names.each do |name|
      find_or_create_by!(user_id: nil, name: name)
    end
  end

  def default?
    user_id.nil?
  end

  def display_name
    return name unless default?

    I18n.t("task_categories.defaults.#{name.parameterize.underscore}", default: name)
  end

  private

  def normalize_name
    self.name = name.strip if name
  end
end
