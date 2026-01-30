class Project < ApplicationRecord
  # Enable version tracking with metadata
  has_paper_trail versions: {
    scope: -> { order("id desc") }
  },
  meta: {
    user_id: :user_id_for_paper_trail,
    ip: :ip_for_paper_trail,
    user_agent: :user_agent_for_paper_trail
  }
  
  has_many :tasks, dependent: :destroy
  has_many :comments, dependent: :destroy
  has_many :statuses, dependent: :destroy
  belongs_to :user

  validates :title, presence: true
  validates :default_priority, inclusion: { in: %w[low medium high leisure] }, allow_nil: true
  validates :color, inclusion: { in: %w[red orange yellow green blue purple pink gray], message: "must be a valid color" }, allow_nil: true, allow_blank: true
  
  before_save :update_last_activity
  before_create :set_initial_activity
  after_create :create_default_statuses
  
  scope :not_completed, -> { 
    joins(:tasks)
      .where(tasks: { completed: false })
      .distinct
  }
  
  # Color-related methods
  def color_classes
    return '' unless color.present?
    
    case color
    when 'red'
      'border-l-4 border-l-red-500 bg-red-50'
    when 'orange'
      'border-l-4 border-l-orange-500 bg-orange-50'
    when 'yellow'
      'border-l-4 border-l-yellow-500 bg-yellow-50'
    when 'green'
      'border-l-4 border-l-green-500 bg-green-50'
    when 'blue'
      'border-l-4 border-l-blue-500 bg-blue-50'
    when 'purple'
      'border-l-4 border-l-purple-500 bg-purple-50'
    when 'pink'
      'border-l-4 border-l-pink-500 bg-pink-50'
    when 'gray'
      'border-l-4 border-l-gray-500 bg-gray-50'
    else
      ''
    end
  end

  def color_badge_classes
    return '' unless color.present?
    
    case color
    when 'red'
      'bg-red-100 text-red-800 border-red-200'
    when 'orange'
      'bg-orange-100 text-orange-800 border-orange-200'
    when 'yellow'
      'bg-yellow-100 text-yellow-800 border-yellow-200'
    when 'green'
      'bg-green-100 text-green-800 border-green-200'
    when 'blue'
      'bg-blue-100 text-blue-800 border-blue-200'
    when 'purple'
      'bg-purple-100 text-purple-800 border-purple-200'
    when 'pink'
      'bg-pink-100 text-pink-800 border-pink-200'
    when 'gray'
      'bg-gray-100 text-gray-800 border-gray-200'
    else
      ''
    end
  end

  def completion_percentage
    return 0 if tasks.empty?
    ((tasks.where(completed: true).count.to_f / tasks.count) * 100).round
  end

  def status
    return 'not_started' if tasks.empty?
    return 'completed' if completion_percentage == 100
    not_started_name = Status.default_statuses[:not_started]
    return 'in_progress' if tasks.not_completed.joins(:status).where.not(statuses: { name: not_started_name }).exists?
    return 'in_progress' if completion_percentage > 0
    'not_started'
  end

  # Helper method to find a status by its default key
  def status_by_key(key)
    statuses.find_by(name: Status.default_statuses[key])
  end

  # Helper method to create a task with default status
  def create_task!(attributes = {})
    tasks.create!(attributes.merge(status: status_by_key(:not_started)))
  end

  # Helper method to build a task with default status
  def build_task(attributes = {})
    tasks.build(attributes.merge(status: status_by_key(:not_started)))
  end

  # Public method to create default statuses
  def create_default_statuses!(force: false)
    return if statuses.any? && !force  # Don't recreate if statuses already exist (unless forced)
    Status.default_statuses.each do |key, name|
      statuses.find_or_create_by!(name: name)
    end
  end

  # I18n display methods
  def default_priority_display
    I18n.t("priorities.#{default_priority}")
  end

  def color_display
    return 'None' unless color.present?
    color.titleize
  end

  private

  def set_initial_activity
    self.last_activity_at = Time.current
  end

  def update_last_activity
    self.last_activity_at = Time.current
  end

  def create_default_statuses
    Status.default_statuses.each do |key, name|
      statuses.create!(name: name)
    end
  end

  # PaperTrail metadata methods
  def user_id_for_paper_trail
    PaperTrail.request.whodunnit
  end
  
  def ip_for_paper_trail
    PaperTrail.request.controller_info[:ip]
  end
  
  def user_agent_for_paper_trail
    PaperTrail.request.controller_info[:user_agent]
  end
end
