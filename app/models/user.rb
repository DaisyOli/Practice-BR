class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :invitable, :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable
  
  has_many :activities, foreign_key: :teacher_id, dependent: :destroy
  has_many :students, -> { where(role: %w[student trial]) }, class_name: 'User', foreign_key: :invited_by_id
  has_many :quiz_attempts, dependent: :destroy
  has_many :push_subscriptions, dependent: :destroy
  has_many :audio_transcriptions, dependent: :destroy
  
  ROLES = %w[teacher student trial].freeze
  LANGUAGES = %w[en pt fr].freeze
  CEFR_LEVELS = %w[A1 A2 B1 B2 C1].freeze
  DEFAULT_LANGUAGE = 'pt'.freeze
  PROFESSIONAL_TYPES = %w[OPCO eCPF].freeze

  scope :teachers, -> { where(role: 'teacher') }
  scope :students, -> { where(role: 'student') }
  scope :trials,   -> { where(role: 'trial') }

  validates :role, presence: true, inclusion: { in: ROLES }
  validates :language, presence: true, inclusion: { in: LANGUAGES }
  validates :name, length: { maximum: 50 }, allow_blank: true
  validates :level, presence: true, inclusion: { in: CEFR_LEVELS }, if: :trial?
  validates :professional_type, inclusion: { in: PROFESSIONAL_TYPES }, allow_blank: true

  before_validation :set_default_language, on: :create
  after_commit :notify_admin_if_teacher_joined

  def admin?
    admin == true
  end

  def teacher?
    role == 'teacher'
  end

  def student?
    role == 'student'
  end

  def trial?
    role == 'trial'
  end

  def student_like?
    student? || trial?
  end

  def trial_expired?
    trial? && (trial_expires_at.nil? || trial_expires_at < Time.current)
  end

  # Cartão recusado não corta o acesso na hora: o aluno tem estes dias pra
  # atualizar o pagamento. O Stripe segue tentando o cartão nesse período, então
  # a maior parte dos casos se resolve sozinha (cartão vencido é a causa mais
  # comum) sem ninguém perder acesso nem receita.
  PAYMENT_GRACE_DAYS = 7

  def payment_past_due?
    subscription_status == "past_due"
  end

  # Marca o início da tolerância. Só na PRIMEIRA falha: o Stripe reenvia
  # invoice.payment_failed a cada nova tentativa, e reiniciar a contagem em cada
  # uma delas faria a tolerância nunca expirar.
  def mark_payment_past_due!
    update!(subscription_status: "past_due", past_due_since: past_due_since || Time.current)
  end

  def clear_payment_past_due!(status: "active")
    update!(subscription_status: status, past_due_since: nil)
  end

  # Deliberadamente `false` quando past_due_since é nil: sem a data não há como
  # contar a tolerância, e trancar um aluno pagante por falta de dado é pior que
  # dar acesso a mais por alguns dias.
  def payment_grace_expired?
    payment_past_due? && past_due_since.present? &&
      past_due_since < PAYMENT_GRACE_DAYS.days.ago
  end

  def payment_grace_days_left
    return nil unless payment_past_due? && past_due_since.present?

    remaining = ((past_due_since + PAYMENT_GRACE_DAYS.days) - Time.current) / 1.day
    [remaining.ceil, 0].max
  end

  def trial_exhausted?
    trial? && trial_activities_used.to_i >= 3
  end

  DAILY_STUDENT_LIMIT = 5

  def trial_access_active?
    trial? && !trial_expired? && !trial_exhausted?
  end

  def daily_limit_reached?
    return false unless student?
    daily_quiz_date == Date.current && daily_quiz_count.to_i >= DAILY_STUDENT_LIMIT
  end

  def increment_daily_count!
    return unless student?
    if daily_quiz_date == Date.current
      increment!(:daily_quiz_count)
    else
      update!(daily_quiz_count: 1, daily_quiz_date: Date.current)
    end
  end

  def language_name
    language_name_for(language)
  end

  def language_name_for(lang_code)
    case lang_code.to_s
    when 'pt' then 'Português'
    when 'en' then 'English'
    when 'fr' then 'Français'
    else 'English'
    end
  end

  def display_name
    name.present? ? name : email.split('@').first.capitalize
  end

  def greeting_name
    name.presence
  end

  def accessible_levels
    return [] if level.blank?
    idx = CEFR_LEVELS.index(level)
    idx ? CEFR_LEVELS[0..idx] : []
  end

  def level_assigned?
    level.present?
  end

  # Peso decrescente por distância do nível declarado: favorece o nível do
  # aluno mas dá espaço real pros de baixo, já que o nível autodeclarado
  # (sobretudo no trial) costuma vir inflado.
  NEXT_ACTIVITY_LEVEL_WEIGHTS = [0.5, 0.3, 0.2].freeze

  # Só ajusta pelo desempenho real depois de tentativas suficientes no
  # próprio nível — com menos que isso a média não é um sinal confiável.
  MIN_ATTEMPTS_FOR_ADAPTIVE_WEIGHTS = 3

  def weighted_priority_levels
    levels = accessible_levels.reverse # próprio nível primeiro, depois descendente
    return levels if levels.size <= 1

    pool = levels.each_with_index.map { |lvl, i| [lvl, NEXT_ACTIVITY_LEVEL_WEIGHTS[i] || NEXT_ACTIVITY_LEVEL_WEIGHTS.last] }
    shift_weight_toward_lower_levels!(pool)

    ordered = []
    while pool.any?
      total = pool.sum { |_, weight| weight }
      draw  = rand * total
      cumulative = 0
      chosen_index = pool.index { |_, weight| (cumulative += weight) >= draw }
      ordered << pool.delete_at(chosen_index || pool.size - 1).first
    end
    ordered
  end

  private

  # Se o aluno já tem tentativas suficientes no próprio nível declarado e
  # está reprovando nelas, puxa peso desse nível pros mais fáceis logo
  # abaixo — sinal de que o nível autodeclarado está inflado.
  def shift_weight_toward_lower_levels!(pool)
    lower_levels = pool[1..]
    return if lower_levels.blank?

    own_level_attempts = quiz_attempts.joins(:activity).where(activities: { level: level })
    return if own_level_attempts.count < MIN_ATTEMPTS_FOR_ADAPTIVE_WEIGHTS

    avg_score = own_level_attempts.average(:score).to_f
    return if avg_score >= QuizAttempt::PASSING_SCORE

    shrink_factor = (1 - avg_score / QuizAttempt::PASSING_SCORE).clamp(0.0, 1.0)
    shrink = pool[0][1] * shrink_factor
    pool[0][1] -= shrink
    lower_levels.each { |entry| entry[1] += shrink / lower_levels.size }
  end

  def set_default_language
    self.language ||= DEFAULT_LANGUAGE
  end

  def notify_admin_if_teacher_joined
    return unless teacher?
    return unless saved_change_to_invitation_accepted_at? && invitation_accepted_at.present?
    AdminMailer.new_teacher_notification(self).deliver_later
  end
end
