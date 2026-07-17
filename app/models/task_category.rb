class TaskCategory < ApplicationRecord
  COLORS = %w[red orange yellow green blue purple pink gray].freeze

  DEFAULT_CATEGORY_COLORS = {
    "Feature" => "blue",
    "Fix" => "red",
    "Tech Debt" => "orange",
    "Chore" => "gray",
    "Documentation" => "purple"
  }.freeze

  belongs_to :user, optional: true
  has_many :tasks, dependent: :nullify

  validates :name, presence: true, uniqueness: { scope: :user_id, case_sensitive: false }
  validates :color, inclusion: { in: COLORS, message: "must be a valid color" }, allow_nil: true, allow_blank: true

  before_save :normalize_name

  scope :default_categories, -> { where(user_id: nil) }
  scope :custom_categories, -> { where.not(user_id: nil) }

  def self.default_category_names
    DEFAULT_CATEGORY_COLORS.keys
  end

  # Idempotent: safe to call from seeds, controllers, or anywhere the default
  # list needs to be guaranteed to exist (the test DB is loaded from schema.rb,
  # not replayed migrations, so a migration-only seed isn't enough). Also
  # backfills a preset color for any default category that doesn't have one
  # yet (e.g. one created before colors existed), without ever overwriting a
  # color a user has since chosen for it.
  def self.ensure_default_categories!
    DEFAULT_CATEGORY_COLORS.each do |name, color|
      category = find_or_create_by!(user_id: nil, name: name) { |c| c.color = color }
      category.update!(color: color) if category.color.blank?
    end
  end

  def default?
    user_id.nil?
  end

  def display_name
    return name unless default?

    I18n.t("task_categories.defaults.#{name.parameterize.underscore}", default: name)
  end

  def badge_classes
    case color
    when 'red'
      'bg-red-100 text-red-800'
    when 'orange'
      'bg-orange-100 text-orange-800'
    when 'yellow'
      'bg-yellow-100 text-yellow-800'
    when 'green'
      'bg-green-100 text-green-800'
    when 'blue'
      'bg-blue-100 text-blue-800'
    when 'purple'
      'bg-purple-100 text-purple-800'
    when 'pink'
      'bg-pink-100 text-pink-800'
    when 'gray'
      'bg-gray-100 text-gray-800'
    else
      'bg-teal-100 text-teal-800'
    end
  end

  private

  def normalize_name
    self.name = name.strip if name
  end
end
