# app/services/activities_index_service.rb
class ActivitiesIndexService
  attr_reader :user, :level

  def initialize(params:, current_user:)
    @params = params
    @current_user = current_user
  end

  def call
    activities = fetch_activities
    activity_ids = activities.pluck(:id)
    {
      activities:          activities,
      current_level:       @params[:level],
      activities_by_level: fetch_activities_by_level,
      best_attempts:       fetch_best_attempts(activity_ids),
      attempt_stats:       fetch_attempt_stats(activity_ids)
    }
  end

  private

  def fetch_activities
    if @current_user.student?
      # .page para a view poder chamar total_pages mesmo na coleção vazia
      return Activity.none.page(@params[:page]).per(9) unless @current_user.level_assigned?
      activities = Activity.published.where(level: @current_user.accessible_levels)
    elsif @params[:arquivadas] == '1'
      # Ponto 1.5: as arquivadas só aparecem neste filtro, para a dona (e para o
      # admin, que pode arquivar a de qualquer uma).
      activities = @current_user.admin? ? Activity.archived : Activity.archived.where(teacher: @current_user)
    else
      # Professora vê as publicadas de todo mundo + os próprios rascunhos.
      # Rascunho é privado: o de outra professora não aparece (e os botões
      # de Revisar/Editar da lista só valem para atividades próprias).
      activities = Activity.published.or(Activity.where(draft: true, teacher: @current_user))
    end

    # with_size e os anexos de vídeo e áudio: o tempo de cada cartão sem uma
    # consulta por cartão (ponto 2.2, telas da professora em 18/11/2026).
    activities = activities.includes(:activity_ratings).with_size
                           .with_attached_video_file
                           .with_attached_audio_file

    activities = activities.with_attached_image_file if @params[:view] == 'grid'

    activities = activities.where(level: @params[:level]) if @params[:level].present?
    activities = activities.where("title ILIKE ?", "%#{@params[:search]}%") if @params[:search].present?
    activities = activities.where(ai_generated: true) if @params[:origem] == 'ia'
    activities = activities.where(ai_generated: [false, nil]) if @params[:origem] == 'manual'

    activities = apply_competency_filter(activities, @params[:competencia])

    apply_sorting(activities).page(@params[:page]).per(9)
  end

  def apply_sorting(activities)
    case @params[:sort]
    when 'antigos'
      activities.order(created_at: :asc)
    when 'titulo'
      activities.order(title: :asc)
    when 'tentativas'
      activities.left_joins(:quiz_attempts)
                .group('activities.id')
                .order('COUNT(quiz_attempts.id) DESC')
    when 'duracao'
      # "⏱ Mais longas", para achar o que cortar (pedido da Daisy, 18/11/2026).
      # O tempo sai das palavras do texto e do trecho do vídeo, contados em
      # Ruby, então a ordem também; são poucas centenas de atividades.
      Kaminari.paginate_array(activities.to_a.sort_by { |activity| [-activity.estimated_minutes, activity.id] })
    else # 'recentes' ou padrão
      activities.order(created_at: :desc)
    end
  end

  def fetch_activities_by_level
    cache_key = @current_user.student? ? ["activities_by_level", @current_user.id] : ["activities_by_level", "teacher"]
    Rails.cache.fetch(cache_key, expires_in: 1.hour) do
      if @current_user.student?
        return {} unless @current_user.level_assigned?
        Activity.published.where(level: @current_user.accessible_levels).group_by(&:level)
      else
        Activity.all.group_by(&:level)
      end
    end
  end

  def fetch_attempt_stats(activity_ids)
    return { counts: {}, unique_users: {} } if activity_ids.empty?

    counts = QuizAttempt.where(activity_id: activity_ids)
                        .group(:activity_id)
                        .count

    unique_users = QuizAttempt.where(activity_id: activity_ids)
                              .where.not(user_id: nil)
                              .group(:activity_id)
                              .distinct
                              .count(:user_id)

    { counts: counts, unique_users: unique_users }
  end

  def apply_competency_filter(activities, competencia)
    case competencia
    when 'co'
      av_ids = ActiveStorage::Attachment
        .where(record_type: 'Activity', name: %w[video_file audio_file])
        .pluck(:record_id)
      activities.where("video_url IS NOT NULL AND video_url != ''")
               .or(activities.where(id: av_ids))
    when 'ce'
      av_ids = ActiveStorage::Attachment
        .where(record_type: 'Activity', name: %w[video_file audio_file])
        .pluck(:record_id)
      activities.where(video_url: [nil, '']).where.not(id: av_ids)
    when 'ee'
      oe_ids = Question.where(question_type: 'open_ended').distinct.pluck(:activity_id)
      oe_ids.any? ? activities.where(id: oe_ids) : activities.none
    else
      activities
    end
  end

  def fetch_best_attempts(activity_ids)
    return {} unless @current_user.student?

    Rails.cache.fetch(["best_attempts", @current_user.id], expires_in: 30.minutes) do
      attempts = @current_user.quiz_attempts
                            .where(activity_id: activity_ids)
                            .group(:activity_id)
                            .select('activity_id, MAX(score) as max_score')
      
      attempts.each_with_object({}) do |attempt, hash|
        hash[attempt.activity_id] = attempt.max_score
      end
    end
  end
end 