class ActivitiesController < ApplicationController
  include QuizManagement
  
  before_action :authenticate_user!
  # Rastreadores de preview (WhatsApp, Facebook, etc.) buscam o link sem sessão
  # nenhuma. Sem isto, caem no redirect pro login e o preview mostra a tela
  # de login em vez do card da atividade.
  # ATENÇÃO: `only:` + `if:` juntos no skip_before_action NÃO funcionam como
  # "E" (o Rails trata como cláusulas independentes e o skip acaba valendo pra
  # qualquer request de :resolve_quiz, com ou sem crawler). Por isso as duas
  # condições vão dentro de uma única lambda.
  skip_before_action :authenticate_user!, if: -> { action_name == "resolve_quiz" && crawler_request? }
  before_action :set_activity, only: [:show, :edit, :update, :destroy, :resolve_quiz, :submit_quiz, :quiz_results, :grading_status, :transcribe_audio, :clear_content, :clear_attempt_history, :review_draft, :publish_draft, :adapt, :archive, :unarchive]
  before_action :preload_exercise_associations, only: [:show]
  before_action :authorize_teacher, only: [:new, :create, :edit, :update, :destroy, :generate_with_ai, :generate_from_video, :generation_wait, :generation_status, :review_draft, :publish_draft, :adapt, :archive, :unarchive]
  before_action :check_trial_level_restriction!, only: [:show, :resolve_quiz, :submit_quiz]

  # User-Agents dos rastreadores que geram o card de preview de link. Não é
  # uma barreira de segurança (User-Agent pode ser falsificado) — por isso o
  # preview mostra só título/descrição/capa, nunca as perguntas da atividade.
  CRAWLER_USER_AGENTS = /facebookexternalhit|Facebot|WhatsApp|Twitterbot|LinkedInBot|Slackbot|TelegramBot|Discordbot|SkypeUriPreview|Google-InspectionTool|Pinterest/i

  def index
    service_result = ActivitiesIndexService.new(params: params, current_user: current_user).call
    @activities        = service_result[:activities]
    @current_level     = service_result[:current_level]
    @activities_by_level = service_result[:activities_by_level]
    @attempt_stats     = service_result[:attempt_stats]

    if current_user.student_like?
      @best_attempts = service_result[:best_attempts]
      load_completed_exercises
    end
  end

  def show
    @questions = load_questions
    
    if current_user.student_like?
      redirect_to solve_activity_path(@activity)
    end
  end

  def resolve_quiz
    if crawler_request?
      render "activities/link_preview", layout: false and return
    end

    if current_user.student_like? && @activity.draft?
      redirect_to student_dashboard_path, alert: "Esta atividade ainda não está disponível." and return
    end
    return redirect_away_from_archived if current_user.student_like? && @activity.archived?
    viewing_results    = params[:show_score] == 'true' && session[:quiz_attempt_id].present?
    already_attempted  = current_user.student? && current_user.quiz_attempts.exists?(activity_id: @activity.id)
    if current_user.student? && current_user.daily_limit_reached? && !viewing_results && !already_attempted
      redirect_to student_dashboard_path, flash: { daily_limit: true } and return
    end
    @questions = quiz_questions
    # Pílula: o desafio de escrita é o último passo, opcional. Quem refaz a
    # pílula e já tinha escrito fica sabendo o que acontece com o texto antigo.
    @writing_challenge  = @activity.writing_challenge
    @previous_challenge = current_user.quiz_attempts.find_by(activity_id: @activity.id)&.challenge_entry if @writing_challenge
    record_trial_first_activity_opened

    if params[:show_score] == 'true' && session[:quiz_attempt_id].present?
      @quiz_attempt = QuizAttempt.find_by(id: session[:quiz_attempt_id])
      if @quiz_attempt && @quiz_attempt.activity_id == @activity.id
        @show_score = true
        @score = @quiz_attempt.score
        @total_correct = @quiz_attempt.results["total_correct"]
        @total_questions = @quiz_attempt.results["total_questions"]
      end
    else
      session.delete(:show_score_data) if session[:show_score_data]&.dig("activity_id") == @activity.id
    end
  end

  def submit_quiz
    return redirect_away_from_archived if current_user&.student_like? && @activity.archived?

    result = QuizSubmissionService.new(
      activity: @activity,
      user: current_user,
      params: params,
      session: session
    ).call

    # Medição (ponto 2.1): esta abertura da página terminou em envio. Se o
    # aviso do navegador ainda não chegou, a linha nasce aqui.
    if result[:success] && current_user.student_like?
      ActivityVisit.record!(user: current_user, activity: @activity, token: params[:visit_token], submitted: true)
    end

    if result[:success] && result[:show_score]
      session[:show_score_data] = {
        score: result[:score],
        total_correct: result[:total_correct],
        total_questions: result[:total_questions],
        activity_id: @activity.id
      }
    end

    if result[:success]
      redirect_to result[:redirect_path], notice: result[:notice]
    else
      redirect_to result[:redirect_path], alert: result[:alert]
    end
  end

  def transcribe_audio
    audio = params[:audio]
    return render json: { error: "Nenhum áudio recebido." }, status: :unprocessable_entity unless audio

    transcription = AudioTranscription.create!(user: current_user, status: "queued")

    # O attach grava o registro no banco e só depois sobe o arquivo pro
    # Cloudinary. Se o upload falha (de 29/07 a 10/10/2026 a chave estava sem
    # permissão), o job nunca era enfileirado: a transcrição ficava "queued"
    # pra sempre e o aluno via "Erro de conexão". Agora ela vira "failed" e o
    # aluno recebe uma mensagem que diz o que aconteceu.
    begin
      transcription.audio_file.attach(io: audio, filename: audio.original_filename, content_type: audio.content_type)
      enqueued = AudioTranscriptionJob.perform_later(transcription.id)
      raise "AudioTranscriptionJob não foi enfileirado" unless enqueued
    rescue => e
      Rails.logger.error "transcribe_audio: #{e.class} - #{e.message}"
      Sentry.capture_exception(e)
      error = "Não conseguimos receber seu áudio. Tente digitar sua resposta."
      transcription.update(status: "failed", error_message: error)
      return render json: { error: error }, status: :service_unavailable
    end

    render json: { transcription_id: transcription.id }
  end

  def transcription_status
    transcription = current_user.audio_transcriptions.find_by(id: params[:id])
    return render json: { status: "failed", error: "Transcrição não encontrada." } unless transcription

    if transcription.done?
      render json: { status: "done", text: transcription.text }
    elsif transcription.failed?
      render json: { status: "failed", error: transcription.error_message }
    else
      render json: { status: "queued" }
    end
  end

  def quiz_results
    @quiz_attempt = find_quiz_attempt
    return redirect_to solve_activity_path(@activity, locale: I18n.locale),
                        alert: t('messages.answer_quiz_first') if @quiz_attempt.nil?

    @questions      = @activity.questions.index_by(&:id)
    @quiz_results   = @quiz_attempt.normalized_results(@questions)
    @existing_rating = current_user&.student_like? ? @activity.rating_by_user(current_user) : nil
    @next_activity   = next_activity_for(current_user)
    render 'quiz_results'
  rescue => e
    Rails.logger.error "Erro ao mostrar resultados: #{e.message}\n#{e.backtrace.join("\n")}"
    redirect_to activities_path, alert: "Ocorreu um erro ao exibir os resultados. Tente novamente."
  end

  # Consultado pela tela de resultados enquanto a correção por IA roda em background
  def grading_status
    attempt = find_quiz_attempt
    render json: { pending: attempt.present? && attempt.ai_grading_pending? }
  end

  def generate_with_ai
    if request.get?
      @activity = Activity.new
      return
    end

    prompt = params[:ai_prompt].to_s.strip
    if prompt.blank?
      flash.now[:alert] = "Por favor, descreva a atividade que deseja gerar."
      @activity = Activity.new
      return render :generate_with_ai, status: :unprocessable_entity
    end

    # A chamada à IA roda em background (AiActivityGenerationJob): dentro da
    # requisição ela estourava o limite de 30s do Heroku (H12)
    generation = AiGeneration.create!(teacher: current_user, kind: "prompt",
                                      request_params: { prompt: prompt })
    AiActivityGenerationJob.perform_later(generation.id)
    redirect_to generation_wait_activities_path(id: generation.id)
  end

  def generation_wait
    @generation = find_generation
    redirect_to activities_path, alert: t('messages.permission_denied') unless @generation
  end

  def generation_status
    generation = find_generation
    return render json: { status: "failed" } unless generation

    payload = { status: generation.status }
    payload[:redirect_url] = review_draft_activity_path(generation.activity) if generation.done? && generation.activity
    render json: payload
  end

  def generate_from_video
    if request.get?
      return
    end

    url = params[:youtube_url].to_s.strip
    if url.blank?
      flash.now[:alert] = "Por favor, cole a URL do vídeo do YouTube."
      return render :generate_from_video, status: :unprocessable_entity
    end

    # A cópia do YouTube gruda cada tempo na fala ("6:126 minutos e 12
    # segundoso orelhão"); a limpeza devolve "6:12 o orelhão". Ver VideoTranscript.
    transcript = VideoTranscript.clean(params[:transcript])
    if transcript.blank?
      flash.now[:alert] = "A transcrição está vazia. Cole o texto da transcrição do vídeo."
      return render :generate_from_video, status: :unprocessable_entity
    end

    # Em pílulas (padrão) ou vídeo inteiro; nas pílulas, a quantidade é da
    # professora (2 a 5) ou da IA. Ver ActivityFromVideoService.
    mode = ActivityFromVideoService::MODES.include?(params[:mode]) ? params[:mode] : "pills"
    if mode == "pills" && !ActivityFromVideoService.timestamps?(transcript)
      flash.now[:alert] = "Para dividir em pílulas, cole a transcrição com os tempos (0:05, 1:23...). " \
                          "Ou escolha \"Vídeo inteiro\", que não precisa deles."
      return render :generate_from_video, status: :unprocessable_entity
    end

    generation = AiGeneration.create!(teacher: current_user, kind: "video", request_params: {
      youtube_url: url,
      transcript:  transcript,
      level_hint:  params[:level_hint].presence,
      mode:        mode,
      pill_count:  params[:pill_count].presence
    })
    AiActivityGenerationJob.perform_later(generation.id)
    redirect_to generation_wait_activities_path(id: generation.id)
  end

  # 📦 Arquivar (ponto 1.5): tira a atividade de circulação para os alunos, e as
  # tentativas, notas, textos e horas de formação ficam. É o caminho no lugar de
  # excluir, que apaga tudo isso para sempre.
  def archive
    return redirect_to(activities_path, alert: t('messages.permission_denied')) unless owns_activity?

    @activity.archive!
    redirect_to activity_path(@activity),
                notice: "Atividade arquivada. Os alunos não a veem mais, e o histórico continua guardado. Ela fica no filtro \"Arquivadas\"."
  end

  def unarchive
    return redirect_to(activities_path, alert: t('messages.permission_denied')) unless owns_activity?

    @activity.unarchive!
    redirect_to activity_path(@activity), notice: "Atividade de volta em circulação."
  end

  # ✂️ Adaptar em pílulas (ponto 1.4). GET mostra o que vai acontecer e, se a
  # atividade tiver vídeo, pede a transcrição com tempos; POST põe a IA para
  # trabalhar em background e leva para a mesma tela de espera da geração,
  # que termina na revisão da primeira pílula.
  def adapt
    unless owns_activity?
      return redirect_to activities_path, alert: t('messages.permission_denied')
    end
    if @activity.pill?
      return redirect_to activity_path(@activity), alert: "Esta atividade já é uma pílula."
    end
    return if request.get?

    transcript = VideoTranscript.clean(params[:transcript])
    if @activity.video_url.present? && transcript.blank?
      flash.now[:alert] = "Cole a transcrição do vídeo com os tempos, para cada pílula ganhar o seu trecho."
      return render :adapt, status: :unprocessable_entity
    end

    generation = AiGeneration.create!(teacher: current_user, kind: "adapt",
                                      request_params: { source_activity_id: @activity.id,
                                                        transcript: transcript.presence })
    AiActivityGenerationJob.perform_later(generation.id)
    redirect_to generation_wait_activities_path(id: generation.id)
  end

  def review_draft
    unless owns_activity?
      redirect_to activities_path, alert: t('messages.permission_denied') and return
    end
    @questions           = @activity.questions.open_ended_last.to_a
    @sentence_orderings  = @activity.sentence_orderings.to_a
    @paragraph_orderings = @activity.paragraph_orderings.includes(:paragraph_sentences).to_a
    @column_matchings    = @activity.column_matchings.includes(:matching_pairs).to_a
  end

  def publish_draft
    unless owns_activity?
      redirect_to activities_path, alert: t('messages.permission_denied') and return
    end

    if @activity.update(draft: false, published_at: Time.current)
      # Série: só a parte 1 avisa os alunos. As outras chegam pela "Próxima
      # atividade", logo depois da anterior; três avisos seriam barulho.
      notify_students_of_new_activity(@activity) unless @activity.series? && @activity.series_position > 1
      redirect_to activity_path(@activity), notice: "Atividade publicada com sucesso!"
    else
      redirect_to review_draft_activity_path(@activity),
                  alert: "Erro ao publicar: #{@activity.errors.full_messages.join(', ')}"
    end
  end

  def new
    @activity = Activity.new
  end

  def create
    @activity = Activity.new(activity_params)
    @activity.teacher = current_user

    if @activity.save
      redirect_to activity_path(@activity), notice: t('messages.activity_created')
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    unless owns_activity?
      redirect_to activities_path, alert: t('messages.permission_denied') and return
    end
  end

  def update
    unless owns_activity?
      redirect_to activities_path, alert: t('messages.permission_denied')
      return
    end

    # Guardar valores anteriores para comparar após o update
    had_statement = @activity.statement.present?
    had_media = @activity.media_url.present?
    had_explanation = @activity.explanation_text.present?

    if @activity.update(activity_params)
      # Determinar o tipo de conteúdo que foi adicionado ou atualizado
      ultimo_conteudo = nil
      
      # Verificar qual conteúdo foi adicionado ou atualizado
      if params[:activity][:statement].present?
        ultimo_conteudo = 'statement'
      elsif params[:activity][:media_url].present?
        ultimo_conteudo = 'media'
      elsif params[:activity][:video_url].present?
        ultimo_conteudo = 'video'
      elsif params[:activity][:explanation_text].present?
        ultimo_conteudo = 'explanation'
      elsif params[:activity][:audio_file].present?
        ultimo_conteudo = 'audio'
      elsif params[:activity][:image_file].present?
        ultimo_conteudo = 'image_file'
      elsif params[:activity][:video_file].present?
        ultimo_conteudo = 'video_file'
      end
      
      redirect_to activity_path(@activity, ultimo_conteudo: ultimo_conteudo), notice: t('messages.activity_updated')
    elsif params[:activity].key?(:video_start) || params[:activity].key?(:video_end)
      # O trecho se edita no bloco do vídeo, na página da atividade: o erro
      # volta para lá, e não para a tela de edição geral.
      redirect_to activity_path(@activity, anchor: "video"), alert: @activity.errors.full_messages.to_sentence
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # Conteúdos da activity que a professora pode excluir individualmente.
  # attribute: coluna que vira nil | attachment: Active Storage que é purgado
  CLEARABLE_CONTENTS = {
    "statement"   => { attribute: :statement,        notice: "statement_deleted" },
    "media"       => { attribute: :media_url,        notice: "media_deleted" },
    "video"       => { attribute: :video_url,        notice: "video_deleted" },
    "explanation" => { attribute: :explanation_text, notice: "explanation_deleted" },
    "audio"       => { attachment: :audio_file,      notice: "audio_deleted" },
    "image_file"  => { attachment: :image_file,      notice: "image_file_deleted" },
    "video_file"  => { attachment: :video_file,      notice: "video_file_deleted" }
  }.freeze

  def clear_content
    unless owns_activity?
      redirect_to activities_path, alert: t('messages.permission_denied') and return
    end

    config = CLEARABLE_CONTENTS.fetch(params[:content])
    if config[:attribute]
      @activity.update(config[:attribute] => nil)
    else
      @activity.public_send(config[:attachment]).purge
    end

    redirect_to activity_path(@activity, ultima_acao: 'conteudo_excluido'), notice: t("messages.#{config[:notice]}")
  end

  def clear_attempt_history
    @activity = Activity.find_by!(slug: params[:slug])
    
    # Manter apenas a tentativa mais recente
    latest_attempt = current_user.quiz_attempts.where(activity_id: @activity.id).order(created_at: :desc).first
    
    # Remover todas as outras tentativas
    current_user.quiz_attempts.where(activity_id: @activity.id).where.not(id: latest_attempt&.id).destroy_all
    
    redirect_to quiz_results_activity_path(@activity), notice: t('messages.attempt_history_cleared')
  end

  def destroy
    unless current_user&.admin?
      redirect_to activities_path, alert: t('messages.permission_denied') and return
    end

    @activity.destroy
    redirect_to activities_url, notice: t('messages.activity_deleted')
  end

  private

  # Dona da atividade ou admin (o painel do agente de conteúdo lista
  # rascunhos de IA de qualquer professora para revisão).
  def owns_activity?
    @activity.teacher == current_user || current_user&.admin?
  end

  # Atividade arquivada (1.5): o aluno que chega por um link antigo vai para a
  # versão nova, se ela virou pílulas; senão, para o painel. Os resultados que
  # ele já tinha continuam abrindo pela tela de resultado.
  def redirect_away_from_archived
    pilula = @activity.published_adapted_pills.first
    if pilula
      redirect_to solve_activity_path(pilula), notice: "Esta atividade ganhou uma versão mais curta, em pílulas. Comece por aqui 🌱"
    else
      redirect_to student_dashboard_path, alert: "Esta atividade saiu de circulação."
    end
  end

  # A geração pertence à professora; o admin também pode acompanhar
  # (o agente de conteúdo cria gerações em nome da professora titular).
  def find_generation
    if current_user&.admin?
      AiGeneration.find_by(id: params[:id])
    else
      AiGeneration.find_by(id: params[:id], teacher: current_user)
    end
  end

  def notify_students_of_new_activity(activity)
    notifiable_levels = StudentMailer.notifiable_levels_for_activity(activity.level)
    User.where(role: "student", level: notifiable_levels).find_each do |student|
      push_body = student.language == "fr" ? "Un exercice #{activity.level} vous attend !" :
                  student.language == "en" ? "A new #{activity.level} exercise is ready!" :
                                             "Exercício #{activity.level} novo disponível!"
      PushNotificationService.send_to_user(
        student,
        title: "Practice-BR 📖",
        body:  push_body,
        url:   activity_url(activity)
      )
    end
  end

  def set_activity
    @activity = Activity.find_by!(slug: params[:slug])
  end

  def crawler_request?
    request.user_agent.present? && request.user_agent.match?(CRAWLER_USER_AGENTS)
  end

  def preload_exercise_associations
    return unless current_user&.teacher?
    @activity = Activity.includes(
      column_matchings:    :matching_pairs,
      paragraph_orderings: :paragraph_sentences
    ).find(@activity.id)
  end

  def find_quiz_attempt
    attempt = QuizAttempt.find_by(id: session[:quiz_attempt_id]) if session[:quiz_attempt_id].present?
    # A sessão guarda a ÚLTIMA tentativa enviada, de qualquer atividade. Sem
    # esta conferência, quem enviava a atividade A e abria o resultado da B via
    # a tentativa da A, e com o desafio da pílula escreveria na atividade errada.
    attempt = nil unless attempt && attempt.activity_id == @activity.id && attempt.user_id == current_user&.id
    attempt ||= current_user&.quiz_attempts&.where(activity_id: @activity.id)&.order(created_at: :desc)&.first
    attempt
  end

  def activity_params
    params.require(:activity).permit(:title, :description, :level, :media_url, :video_url, :video_start, :video_end, :explanation_text, :explanation_is_transcript, :statement, :audio_file, :image_file, :video_file)
  end
  
  def authorize_teacher
    unless current_user&.teacher?
      redirect_to root_path, alert: "Acesso restrito a professores."
    end
  end

  # A próxima atividade oferecida no fim da tela de resultados, para o aluno
  # emendar uma na outra sem voltar ao painel. É a mesma escolha do "Continue
  # estudando" da dashboard (StudentDashboardPresenter): se cada tela escolhesse
  # por conta própria, as duas sugeririam atividades diferentes.
  #
  # Nada é oferecido quando o clique daria numa porta fechada: teste encerrado
  # ou limite diário atingido.
  def next_activity_for(user)
    return nil unless user&.student_like?
    return nil if user.trial? && !user.trial_access_active?
    return nil if user.daily_limit_reached?

    StudentDashboardPresenter.new(
      user:                user,
      activities_by_level: Activity.published.group_by(&:level),
      completed_ids:       user.quiz_attempts.pluck(:activity_id)
    ).continue_activity
  end

  # "Abriu uma atividade" é o degrau do funil entre entrar e terminar: separa
  # quem não achou por onde começar de quem começou e desistiu no meio — dois
  # problemas com soluções diferentes. Uma escrita na vida da conta.
  def record_trial_first_activity_opened
    return unless current_user&.trial? && current_user.first_activity_opened_at.nil?

    current_user.update_column(:first_activity_opened_at, Time.current)
  end

  def check_trial_level_restriction!
    return unless current_user&.trial?
    return unless @activity

    if @activity.level != current_user.level
      redirect_to student_dashboard_path, alert: "Seu acesso trial é apenas para atividades do nível #{current_user.level}."
    end
  end
end
