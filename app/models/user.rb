class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  has_many :projects, dependent: :destroy
  has_many :tasks, dependent: :nullify
  has_many :comments, dependent: :nullify

  validates :name, presence: true
  validates :email, presence: true, 
                   uniqueness: { case_sensitive: false },
                   format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :theme_preference, inclusion: { in: %w[day night auto], allow_blank: true }

  def assigned_tasks
    tasks.where(completed: false).order(due_date: :asc)
  end

  def completed_tasks
    tasks.where(completed: true).order(updated_at: :desc)
  end
end
