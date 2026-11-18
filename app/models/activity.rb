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
  # Até onde cada aluno chegou (ponto 2.1). Medição: vai junto com a atividade.
  has_many :activity_visits, dependent: :delete_all
  # Registro da geração por IA que criou esta atividade. Ao apagar a atividade,
  # zeramos o vínculo (activity_id -> NULL) em vez de barrar: o AiGeneration já
  # é `belongs_to :activity, optional: true` e serve de histórico. Sem isto, o
  # destroy batia na FK fk_rails_7941c1ead7 e estourava 500.
  has_many :ai_generations, dependent: :nullify

  # Pílulas em série (ponto 1.4): a atividade longa de onde a pílula veio, pelo
  # botão "Adaptar em pílulas", e as pílulas que saíram dela. Serve só para o
  # "adaptada de"; a série em si é a `series_key`. Apagar a original não apaga
  # as pílulas nem desfaz a série: só some o "adaptada de".
  belongs_to :source_activity, class_name: "Activity", optional: true
  has_many :adapted_pills, class_name: "Activity", foreign_key: :source_activity_id,
           inverse_of: :source_activity, dependent: :nullify

  has_one_attached :audio_file
  has_one_attached :image_file
  has_one_attached :video_file

  validates :title, presence: true, length: { minimum: 3, maximum: 100 }
  validates :description, presence: true
  validates :level, presence: true
  validates :slug, presence: true, uniqueness: true
  validates :video_start_seconds, :video_end_seconds,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validate  :video_excerpt_consistent

  scope :ordered, -> { order(created_at: :desc) }
  scope :by_level, ->(level) { where(level: level) }
  # "Publicada" é o que o aluno pode ver: nem rascunho, nem arquivada (1.5).
  # O app inteiro decide o que mostrar por aqui (listas, painel, percurso,
  # lembretes, agentes), então arquivar some de todos esses lugares de uma vez.
  scope :published, -> { where(draft: false, archived_at: nil) }
  scope :archived,  -> { where.not(archived_at: nil) }

  # Percurso do nível: até 10 atividades em ordem, escolhidas no painel admin
  # (Admin::PathController). As 3 primeiras são a vitrine do teste — quem testa
  # faz o começo do caminho e, ao assinar, continua da 4ª.
  PATH_SLOTS  = 10
  TRIAL_SLOTS = 3
  scope :in_path, -> { where.not(path_position: nil).order(:path_position) }
  # A ordem das listas do aluno (18/11/2026): as mais novas primeiro, e as
  # partes de uma série juntas e em sequência. Antes, a lista não tinha ordem
  # nenhuma, e a parte 3 da série da Chu Ming aparecia antes da parte 1.
  scope :in_student_order, -> {
    order(Arel.sql("MIN(activities.created_at) OVER (PARTITION BY COALESCE(activities.series_key, activities.id::text)) DESC, " \
                   "activities.series_position ASC NULLS FIRST, activities.id ASC"))
  }

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
  # O tamanho de cada atividade da lista numa consulta só (ponto 2.2). Sem
  # isto, cada cartão faria as próprias contagens. Os métodos de tamanho e
  # tempo usam estes números quando eles vêm; senão, contam sozinhos.
  SIZE_COUNTS = {
    "questions_count"  => "SELECT COUNT(*) FROM questions q WHERE q.activity_id = activities.id",
    "open_ended_count" => "SELECT COUNT(*) FROM questions q WHERE q.activity_id = activities.id AND q.question_type = 'open_ended'",
    "orderings_count"  => "(SELECT COUNT(*) FROM sentence_orderings o WHERE o.activity_id = activities.id) + " \
                          "(SELECT COUNT(*) FROM paragraph_orderings o WHERE o.activity_id = activities.id)",
    "matchings_count"  => "SELECT COUNT(*) FROM column_matchings m WHERE m.activity_id = activities.id"
  }.freeze
  scope :with_size, -> { select("activities.*", *SIZE_COUNTS.map { |name, sql| "(#{sql}) AS #{name}" }) }

  before_validation :generate_slug, if: :should_generate_slug?
  # Mudou de nível, sai do percurso: ele foi montado para um nível, e a mesma
  # posição no nível novo pode já estar ocupada.
  before_save :leave_path, if: -> { will_save_change_to_level? && path_position.present? }
  # Trocou ou tirou o vídeo: o trecho marcado era do vídeo antigo. Só quando já
  # havia vídeo: a geração por vídeo grava o trecho antes do link, e ele fica.
  before_save :reset_video_excerpt, if: -> { will_save_change_to_video_url? && video_url_in_database.present? }
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

  # O desafio de escrita da pílula: a pergunta aberta que vira o último passo do
  # quiz, opcional e fora da nota. A IA põe exatamente uma, no
  # fim; se vier mais de uma, só a última vira desafio e as outras continuam no
  # quiz como sempre. nil fora das pílulas.
  def writing_challenge
    return nil unless pill?

    questions.where(question_type: "open_ended").order(:created_at, :id).last
  end

  # Quantos passos o quiz tem: todas as questões (o desafio da pílula é o
  # último passo), as ordenações e as ligações de colunas. É o "1 de N" da tela.
  def quiz_step_count
    questions.size + sentence_orderings.size + paragraph_orderings.size + column_matchings.size
  end

  # ── Tamanho e tempo, para os cartões (ponto 2.2) ──────────────────────
  # "~N min · M exercícios" antes de começar. Calibrado em 18/11/2026 com 89
  # tentativas reais (7 pessoas, sem as contas de teste), mirando a pessoa
  # típica (a mediana), e não a média, que quem demora muito puxa para cima.
  # - A conta antiga (1,5 min por questão) ficava 4,3 min abaixo do real na
  #   mediana. Esta fica a 0,1 min.
  # - Numa tentativa isolada, qualquer conta erra uns 6 a 7 min: entre duas
  #   pessoas, uma leva o dobro da outra. Por isso o "~".
  # - Escrever, ler e o vídeo pesam; o exercício fechado é rápido.
  MINUTES_PER_EXERCISE  = 0.75 # lacuna, escolha, ordenar, ligar colunas
  MINUTES_PER_WRITING   = 4    # questão aberta dentro do quiz
  MINUTES_PER_100_WORDS = 2    # ler o texto de apoio
  # Vídeo sem trecho marcado (a duração não é conhecida). Os vídeos inteiros
  # das atividades antigas somavam isto, e não a duração deles: a pessoa
  # responde enquanto assiste, ou não assiste tudo. Por isso o trecho marcado
  # conta a própria duração, sem passar deste teto (sem dado ainda: nenhuma
  # tentativa com trecho até 18/11).
  MINUTES_WHOLE_VIDEO   = 5
  MINUTES_AUDIO         = 3    # áudio anexado (a duração também não é conhecida; sem dado)
  MIN_MINUTES           = 2

  # Os exercícios que valem nota: o "1 de N" sem o desafio de escrita.
  def exercise_count
    size_summary[:exercises]
  end

  def estimated_minutes
    size_summary[:minutes]
  end

  # O mesmo que `writing_challenge.present?`, sem buscar a questão.
  def writing_challenge?
    size_summary[:challenge]
  end

  def reload(*)
    @size_summary = nil
    super
  end

  # Trecho do vídeo (ponto 1.3): o player do YouTube toca só desse ponto até
  # aquele. O formulário recebe "1:20"; o banco guarda 80. Vazio = vídeo inteiro.
  def video_start = VideoTimestamp.to_label(video_start_seconds)
  def video_end   = VideoTimestamp.to_label(video_end_seconds)

  def video_start=(value)
    assign_video_time(:video_start_seconds, value)
  end

  def video_end=(value)
    assign_video_time(:video_end_seconds, value)
  end

  def video_excerpt?
    video_start_seconds.present? || video_end_seconds.present?
  end

  # A série é a `series_key`, e não a atividade original: assim ela sobrevive
  # à original apagada, e o gerador por vídeo faz séries sem original.
  def series?
    series_key.present? && series_position.present?
  end

  # As partes da série, em ordem. Para o aluno, só as publicadas.
  def series_parts(published_only: true)
    return Activity.none unless series?

    parts = Activity.where(series_key: series_key).where.not(series_position: nil)
    parts = parts.published if published_only
    parts.order(:series_position, :id)
  end

  # "Parte 2 de 3". Conta pela posição entre as partes que existem, e não pelo
  # número gravado: uma parte descartada na revisão não deixa buraco. nil fora
  # de série ou quando só sobrou uma parte.
  def series_label(published_only: true)
    parts = series_parts(published_only: published_only).to_a
    index = parts.index(self)
    return nil if index.nil? || parts.size < 2

    "Parte #{index + 1} de #{parts.size}"
  end

  # Por onde a pessoa entra na série (pedido da Daisy, 18/11/2026): a primeira
  # parte publicada que ela ainda não fez. Oferecer a parte 2 ou a 3 a quem
  # não fez a 1 não faz sentido. Todo lugar que sugere uma atividade passa por
  # aqui: painel, resultado, "Comece por aqui", percurso e emails. Fora de
  # série, ou com a série toda feita, devolve a própria atividade.
  def series_entry_for(done_ids)
    return self unless series?

    series_parts.where.not(id: done_ids).first || self
  end

  # Arquivar (ponto 1.5): sai de circulação para os alunos e sai do percurso,
  # mas as tentativas, notas, textos e horas de formação ficam. Desarquivar
  # devolve à circulação (o percurso, se for o caso, se remonta no painel).
  def archived?
    archived_at.present?
  end

  def archive!
    update!(archived_at: Time.current, path_position: nil)
  end

  def unarchive!
    update!(archived_at: nil)
  end

  # As pílulas que saíram desta atividade e já estão com os alunos: é a deixa
  # para sugerir arquivar a original.
  def published_adapted_pills
    adapted_pills.published.order(:series_position, :id)
  end

  private

  def size_summary
    @size_summary ||= begin
      c = size_counts
      challenge = pill? && c[:open_ended].positive?
      escritas  = c[:open_ended] - (challenge ? 1 : 0)
      fechados  = c[:questions] - c[:open_ended] + c[:orderings] + c[:matchings]
      minutos   = fechados * MINUTES_PER_EXERCISE +
                  escritas * MINUTES_PER_WRITING +
                  reading_words * MINUTES_PER_100_WORDS / 100.0 +
                  media_minutes
      { exercises: fechados + escritas, minutes: [minutos.ceil, MIN_MINUTES].max, challenge: challenge }
    end
  end

  def size_counts
    if has_attribute?(:matchings_count)
      { questions: self[:questions_count].to_i, open_ended: self[:open_ended_count].to_i,
        orderings: self[:orderings_count].to_i, matchings: self[:matchings_count].to_i }
    else
      { questions: questions.size, open_ended: questions.where(question_type: "open_ended").count,
        orderings: sentence_orderings.size + paragraph_orderings.size, matchings: column_matchings.size }
    end
  end

  # O texto que a pessoa lê. A transcrição do vídeo fica de fora: o tempo dela
  # já está no do vídeo.
  def reading_words
    texto = [statement, (explanation_text unless explanation_is_transcript?)].compact.join(" ")
    ActionView::Base.full_sanitizer.sanitize(texto).split.size
  end

  def media_minutes
    if video_url.present?
      return MINUTES_WHOLE_VIDEO unless video_start_seconds && video_end_seconds

      [(video_end_seconds - video_start_seconds) / 60.0, MINUTES_WHOLE_VIDEO].min
    elsif video_file.attached? || media_url.to_s.match?(/youtube\.com|youtu\.be|vimeo\.com|\.(mp4|webm|ogg)(\?.*)?$/i)
      MINUTES_WHOLE_VIDEO
    elsif audio_file.attached?
      MINUTES_AUDIO
    else
      0
    end
  end

  def assign_video_time(column, value)
    parsed = VideoTimestamp.parse(value)
    if parsed == :invalid
      (@invalid_video_times ||= []) << column
    else
      self[column] = parsed
    end
  end

  # Frases inteiras em :base: o app não traduz nome de campo, e "Video start
  # precisa..." não serviria para a professora.
  def video_excerpt_consistent
    Array(@invalid_video_times).uniq.each do |column|
      campo = column == :video_start_seconds ? "O início do trecho" : "O fim do trecho"
      errors.add(:base, "#{campo} precisa estar no formato 1:20 (minutos:segundos)")
    end
    if video_start_seconds && video_end_seconds && video_end_seconds <= video_start_seconds
      errors.add(:base, "O fim do trecho precisa vir depois do início")
    end
  end

  def reset_video_excerpt
    return if will_save_change_to_video_start_seconds? || will_save_change_to_video_end_seconds?

    self.video_start_seconds = nil
    self.video_end_seconds   = nil
  end

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
