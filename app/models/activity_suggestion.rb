class ActivitySuggestion < ApplicationRecord
  belongs_to :teacher, class_name: "User"
  belongs_to :activity, optional: true

  STATUSES = %w[pending approved rejected].freeze

  validates :status, inclusion: { in: STATUSES }
  validates :theme, presence: true
  validates :level_hint, presence: true

  scope :pending,     -> { where(status: 'pending') }
  scope :today,       -> { where(created_at: Time.zone.today.all_day) }
  scope :for_teacher, ->(teacher) { where(teacher_id: teacher.id) }

  def pending?;  status == 'pending';  end
  def approved?; status == 'approved'; end
  def rejected?; status == 'rejected'; end
end
