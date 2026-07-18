class Notification < ApplicationRecord
  belongs_to :user

  validates :title, presence: true

  scope :unread, -> { where(read_at: nil) }
  scope :recent_first, -> { order(created_at: :desc) }

  def self.notify!(user:, title:, body: nil, kind: nil, link_path: nil)
    create!(user: user, title: title, body: body, kind: kind, link_path: link_path)
  end

  def read?
    read_at.present?
  end

  def mark_as_read!
    update!(read_at: Time.current) unless read?
  end
end
