class Activity < ApplicationRecord
  belongs_to :teacher, class_name: 'User'
  has_many :questions, dependent: :destroy
  has_many :quiz_attempts, dependent: :destroy
  has_many :suggestions, dependent: :destroy
  has_many :sentence_orderings, dependent: :destroy
  has_many :paragraph_orderings, dependent: :destroy
  has_many :column_matchings, dependent: :destroy
  has_many :activity_ratings, dependent: :destroy
  # Registro da geração por IA que criou esta atividade. Ao apagar a atividade,
  # zeramos o vínculo (activity_id -> NULL) em vez de barrar: o AiGeneration já
  # é `belongs_to :activity, optional: true` e serve de histórico. Sem isto, o
  # destroy batia na FK fk_rails_7941c1ead7 e estourava 500.
  has_many :ai_generations, dependent: :nullify

  has_one_attached :audio_file
  has_one_attached :image_file
  has_one_attached :video_file

  validates :title, presence: true, length: { minimum: 3, maximum: 100 }
  validates :description, presence: true
  validates :level, presence: true
  validates :slug, presence: true, uniqueness: true
  
  scope :ordered, -> { order(created_at: :desc) }
  scope :by_level, ->(level) { where(level: level) }
  scope :published, -> { where(draft: false) }
  scope :with_questions_count, -> {
    left_outer_joins(:questions)
      .group(:id)
      .select('activities.*, COUNT(questions.id) AS questions_count')
  }

  before_validation :generate_slug, if: :should_generate_slug?
  after_create      :fetch_unsplash_cover
  after_commit      :clear_cache
  
  enum level: {
    A1: 'A1',
    A2: 'A2',
    B1: 'B1',
    B2: 'B2',
    C1: 'C1'
  }

  def to_param
    slug
  end

  def level_color_class
    case level
    when 'A1' then 'bg-info'
    when 'A2' then 'bg-primary'
    when 'B1' then 'bg-success'
    when 'B2' then 'bg-warning'
    when 'C1' then 'bg-danger'
    else 'bg-secondary'
    end
  end

  def estimated_duration
    mins = [questions.size * 2, 5].max
    "~#{mins} min"
  end

  def average_rating
    loaded = activity_ratings.to_a
    return 0 if loaded.empty?
    (loaded.sum(&:stars).to_f / loaded.size).round(1)
  end

  def ratings_count
    activity_ratings.size
  end

  def rating_by_user(user)
    activity_ratings.to_a.find { |r| r.user_id == user.id }
  end

  private

  def generate_slug
    return unless title.present?
    
    # Criar slug base a partir do título
    base_slug = title.downcase
                    .gsub(/[àáâãäå]/, 'a')
                    .gsub(/[èéêë]/, 'e')
                    .gsub(/[ìíîï]/, 'i')
                    .gsub(/[òóôõö]/, 'o')
                    .gsub(/[ùúûü]/, 'u')
                    .gsub(/[ç]/, 'c')
                    .gsub(/[ñ]/, 'n')
                    .gsub(/[^a-z0-9\s-]/, '') # Remove caracteres especiais
                    .gsub(/\s+/, '-')         # Substitui espaços por hífens
                    .gsub(/-+/, '-')          # Remove hífens duplicados
                    .strip
                    .gsub(/^-|-$/, '')        # Remove hífens do início/fim
    
    # Garantir unicidade
    unique_slug = base_slug
    counter = 1
    
    while Activity.where(slug: unique_slug).where.not(id: self.id).exists?
      unique_slug = "#{base_slug}-#{counter}"
      counter += 1
    end
    
    self.slug = unique_slug
  end
  
  def should_generate_slug?
    # O slug não pode mudar depois de gerado: ele fica embutido em formulários
    # já carregados (aluno no meio do exercício) e em links compartilhados
    # (WhatsApp, etc.). Se o slug mudasse a cada edição de título, qualquer
    # sessão/link em andamento vira 404 quando o professor renomeia a atividade.
    slug.blank?
  end
  
  def clear_cache
    Rails.cache.delete_matched("activities*")
    Rails.cache.delete_matched("activity_questions/#{id}*")
    Rails.cache.delete_matched("activities_by_level*")
  end

  def fetch_unsplash_cover
    return if image_file.attached? || media_url.present? || video_url.present?
    query = [title, description].compact.join(" ").first(120)
    result = UnsplashService.new(query).call
    return unless result
    update_columns(
      unsplash_cover_url:    result[:url],
      unsplash_cover_credit: "#{result[:photographer]} | Unsplash"
    )
  rescue StandardError
    nil
  end
end
