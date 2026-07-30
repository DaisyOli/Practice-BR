# Monta tudo que a plataforma guarda sobre uma pessoa, para o direito de acesso e
# de portabilidade (RGPD arts. 15 e 20 · LGPD art. 18, II e V).
#
# A lei pede formato "estruturado, de uso corrente e leitura automática" — daí
# JSON. As chaves estão em português porque quem lê é o titular, não um sistema.
#
# Regra ao mexer aqui: se uma tabela nova passar a guardar dado ligado a uma
# pessoa, ela entra nesta exportação. A conferência é a mesma da exclusão — ver
# as chaves estrangeiras que apontam pra users.
class DataExportService
  AVISO = "Este arquivo contém tudo que a Practice-BR guarda sobre você. " \
          "Não inclui sua senha, que é guardada apenas de forma criptografada e " \
          "não pode ser lida nem por nós.".freeze

  def initialize(user)
    @user = user
  end

  def call
    dados = {
      exportado_em: Time.current.iso8601,
      aviso:        AVISO,
      conta:        conta
    }

    dados[:assinatura]             = assinatura if assinatura?
    dados[:atividades_respondidas] = atividades_respondidas
    dados[:respostas_em_audio]     = respostas_em_audio
    dados[:avaliacoes_que_voce_deu] = avaliacoes
    dados[:notificacoes]           = notificacoes
    dados[:atividades_criadas]     = atividades_criadas if @user.teacher?

    dados
  end

  def filename
    "practice-br-meus-dados-#{Date.current.iso8601}.json"
  end

  private

  def conta
    {
      id:                    @user.id,
      email:                 @user.email,
      nome:                  @user.name,
      papel:                 @user.role,
      idioma:                @user.language,
      nivel:                 @user.level,
      percurso_profissional: @user.professional_type,
      conta_criada_em:       @user.created_at&.iso8601,
      convite_aceito_em:     @user.invitation_accepted_at&.iso8601,
      lembrete_semanal:      @user.weekly_reminder_email
    }.compact
  end

  def assinatura?
    @user.stripe_customer_id.present? || @user.subscription_status.present?
  end

  def assinatura
    {
      situacao:                @user.subscription_status,
      periodo_termina_em:      @user.subscription_current_period_end&.iso8601,
      pagamento_em_atraso_desde: @user.past_due_since&.iso8601,
      id_cliente_stripe:       @user.stripe_customer_id,
      id_assinatura_stripe:    @user.stripe_subscription_id,
      observacao:              "Os dados do seu cartão nunca passaram pelos nossos servidores — " \
                               "ficam só com a Stripe."
    }.compact
  end

  def atividades_respondidas
    @user.quiz_attempts.includes(:activity).order(:created_at).map do |tentativa|
      {
        atividade:            tentativa.activity&.title,
        nivel:                tentativa.activity&.level,
        nota:                 tentativa.score,
        iniciada_em:          tentativa.started_at&.iso8601,
        enviada_em:           tentativa.submitted_at&.iso8601,
        # O jsonb bruto: é onde estão as suas respostas, questão por questão.
        respostas:            tentativa.results,
        comentarios_da_professora: tentativa.teacher_comments.presence
      }.compact
    end
  end

  def respostas_em_audio
    @user.audio_transcriptions.order(:created_at).map do |transcricao|
      {
        texto_transcrito: transcricao.text,
        situacao:         transcricao.status,
        criada_em:        transcricao.created_at&.iso8601,
        observacao:       "A gravação em si foi apagada logo depois de gerar este texto."
      }.compact
    end
  end

  def avaliacoes
    @user.activity_ratings.includes(:activity).order(:created_at).map do |avaliacao|
      {
        atividade:  avaliacao.activity&.title,
        estrelas:   avaliacao.stars,
        comentario: avaliacao.comment,
        feita_em:   avaliacao.created_at&.iso8601
      }.compact
    end
  end

  # Só a existência e a data. O endpoint e as chaves do push são credenciais
  # técnicas do navegador: não dizem nada pra pessoa e exportá-las seria entregar
  # material com que se pode enviar notificação em nome dela.
  def notificacoes
    @user.push_subscriptions.order(:created_at).map do |inscricao|
      {
        dispositivo_registrado_em: inscricao.created_at&.iso8601,
        observacao: "Guardamos o endereço técnico que permite enviar a notificação. " \
                    "Ele não é exportado aqui por ser credencial, não informação sua."
      }
    end
  end

  def atividades_criadas
    @user.activities.order(:created_at).map do |atividade|
      {
        titulo:        atividade.title,
        nivel:         atividade.level,
        criada_em:     atividade.created_at&.iso8601,
        publicada_em:  atividade.published_at&.iso8601,
        rascunho:      atividade.draft,
        gerada_por_ia: atividade.ai_generated
      }.compact
    end
  end
end
