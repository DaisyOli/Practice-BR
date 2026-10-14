class Activity < ApplicationRecord
  belongs_to :teacher, class_name: 'User'
  has_many :questions, dependent: :destroy
  has_many :path_suggestions, dependent: :destroy
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

  # Percurso do nível: até 10 atividades em ordem, escolhidas no painel admin
  # (Admin::PathController). As 3 primeiras são a vitrine do teste — quem testa
  # faz o começo do caminho e, ao assinar, continua da 4ª.
  PATH_SLOTS  = 10
  TRIAL_SLOTS = 3
  scope :in_path, -> { where.not(path_position: nil).order(:path_position) }

  # Grava o percurso de um nível na ordem de `ids`. Limpa e regrava numa
  # transação, para nunca esbarrar no índice único no meio de uma troca de
  # posições. Ignora id repetido, rascunho e atividade de outro nível.
  def self.set_path!(level, ids)
    transaction do
      where(level: level).where.not(path_position: nil).update_all(path_position: nil)
      ids.map(&:to_i).uniq.first(PATH_SLOTS).each.with_index(1) do |id, position|
        published.where(level: level, id: id).update_all(path_position: position)
      end
    end
  end
  scope :with_questions_count, -> {
    left_outer_joins(:questions)
      .group(:id)
      .select('activities.*, COUNT(questions.id) AS questions_count')
  }

  before_validation :generate_slug, if: :should_generate_slug?
  # Mudou de nível, sai do percurso: ele foi montado para um nível, e a mesma
  # posição no nível novo pode já estar ocupada.
  before_save :leave_path, if: -> { will_save_change_to_level? && path_position.present? }
  after_create      :fetch_unsplash_cover
  after_commit      :clear_cache
  # Publicou: o agente do percurso avalia se ela entra no caminho do nível e
  # deixa a sugestão para a Daisy aprovar (PathSuggestion). Nunca muda sozinho.
  after_commit      :request_path_evaluation, if: :just_published?
  
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

  def leave_path
    self.path_position = nil
  end

  def just_published?
    return false if draft?

    previously_new_record? || saved_change_to_draft?
  end

  def request_path_evaluation
    PathSuggestion.request_for_new!(self)
  rescue StandardError => e
    # Uma falha aqui não pode desfazer a publicação da professora.
    Rails.logger.error "[LevelPath] avaliação não pedida para #{id}: #{e.class}: #{e.message}"
  end
end
