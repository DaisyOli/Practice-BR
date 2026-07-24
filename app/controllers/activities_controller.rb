class ActivitiesController < ApplicationController
  include QuizManagement
  
  before_action :authenticate_user!
  before_action :set_activity, only: [:show, :edit, :update, :destroy, :resolve_quiz, :submit_quiz, :quiz_results, :grading_status, :transcribe_audio, :clear_content, :clear_attempt_history, :review_draft, :publish_draft]
  before_action :preload_exercise_associations, only: [:show]
  before_action :authorize_teacher, only: [:new, :create, :edit, :update, :destroy, :generate_with_ai, :generate_from_video, :generation_wait, :generation_status, :review_draft, :publish_draft]
  before_action :check_trial_level_restriction!, only: [:show, :resolve_quiz, :submit_quiz]

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
    if current_user.student_like? && @activity.draft?
      redirect_to student_dashboard_path, alert: "Esta atividade ainda não está disponível." and return
    end
    viewing_results    = params[:show_score] == 'true' && session[:quiz_attempt_id].present?
    already_attempted  = current_user.student? && current_user.quiz_attempts.exists?(activity_id: @activity.id)
    if current_user.student? && current_user.daily_limit_reached? && !viewing_results && !already_attempted
      redirect_to student_dashboard_path, flash: { daily_limit: true } and return
    end
    @questions = load_questions
    
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
    result = QuizSubmissionService.new(
      activity: @activity,
      user: current_user,
      params: params,
      session: session
    ).call

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

    result = WhisperTranscriptionService.new(audio).call
    if result[:success]
      render json: { text: result[:text] }
    else
      render json: { error: result[:error] }, status: :unprocessable_entity
    end
  end

  def quiz_results
    @quiz_attempt = find_quiz_attempt
    return redirect_to solve_activity_path(@activity, locale: I18n.locale),
                        alert: t('messages.answer_quiz_first') if @quiz_attempt.nil?

    @questions      = @activity.questions.index_by(&:id)
    @quiz_results   = @quiz_attempt.normalized_results(@questions)
    @existing_rating = current_user&.student_like? ? @activity.rating_by_user(current_user) : nil
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

    if params[:transcript].to_s.strip.blank?
      flash.now[:alert] = "A transcrição está vazia. Cole o texto da transcrição do vídeo."
      return render :generate_from_video, status: :unprocessable_entity
    end

    generation = AiGeneration.create!(teacher: current_user, kind: "video", request_params: {
      youtube_url: url,
      transcript:  params[:transcript].to_s,
      level_hint:  params[:level_hint].presence
    })
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
      notify_students_of_new_activity(@activity)
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

  def preload_exercise_associations
    return unless current_user&.teacher?
    @activity = Activity.includes(
      column_matchings:    :matching_pairs,
      paragraph_orderings: :paragraph_sentences
    ).find(@activity.id)
  end

  def find_quiz_attempt
    attempt = QuizAttempt.find_by(id: session[:quiz_attempt_id]) if session[:quiz_attempt_id].present?
    attempt ||= current_user&.quiz_attempts&.where(activity_id: @activity.id)&.order(created_at: :desc)&.first
    attempt
  end

  def activity_params
    params.require(:activity).permit(:title, :description, :level, :media_url, :video_url, :explanation_text, :explanation_is_transcript, :statement, :audio_file, :image_file, :video_file)
  end
  
  def authorize_teacher
    unless current_user&.teacher?
      redirect_to root_path, alert: "Acesso restrito a professores."
    end
  end

  def check_trial_level_restriction!
    return unless current_user&.trial?
    return unless @activity

    if @activity.level != current_user.level
      redirect_to student_dashboard_path, alert: "Seu acesso trial é apenas para atividades do nível #{current_user.level}."
    end
  end
end
