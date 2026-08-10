# Toda a conta que a dashboard do aluno precisa, fora da view.
#
# Isto eram ~100 linhas de Ruby no topo de `students/dashboard.html.erb`,
# misturadas com o HTML. Aqui dá pra testar sem renderizar página, e a view
# volta a ser só apresentação.
class StudentDashboardPresenter
  MEDIA_ATTACHMENTS = %w[audio_file video_file image_file].freeze

  attr_reader :user, :completed_ids

  def initialize(user:, activities_by_level:, completed_ids: [], level_filter: nil)
    @user                = user
    @activities_by_level = activities_by_level || {}
    @completed_ids       = completed_ids || []
    @level_filter        = level_filter
  end

  def cefr_levels
    User::CEFR_LEVELS
  end

  def levels_data
    @levels_data ||= cefr_levels.map do |level|
      acts  = @activities_by_level[level] || []
      done  = (completed_ids & acts.map(&:id)).length
      total = acts.count

      {
        level: level,
        acts:  acts,
        done:  done,
        total: total,
        pct:   total.positive? ? ((done.to_f / total) * 100).round : 0,
        empty: acts.empty?
      }
    end
  end

  def total_completed
    @total_completed ||= levels_data.sum { |data| data[:done] }
  end

  def overall_pct
    total = levels_data.sum { |data| data[:total] }
    total.positive? ? ((total_completed.to_f / total) * 100).round : 0
  end

  def accessible_levels
    @accessible_levels ||= user.accessible_levels
  end

  # A atividade sugerida no "Continue estudando". Só faz sentido na visão
  # principal: filtrando por nível, o aluno já disse o que quer.
  def continue_activity
    return @continue_activity if defined?(@continue_activity)

    @continue_activity =
      if filtered? || best_candidate.nil?
        nil
      else
        load_with_media(best_candidate.id)
      end
  end

  # Só aparece quando não sobrou nada pendente: em vez de um espaço vazio,
  # mostra a última que ele fez.
  def last_completed_activity
    return @last_completed_activity if defined?(@last_completed_activity)

    @last_completed_activity =
      if continue_activity.nil? && !filtered? && last_attempt&.activity_id
        load_with_media(last_attempt.activity_id)
      end
  end

  private

  def filtered?
    @level_filter.present?
  end

  def pending_activities
    @pending_activities ||= user.weighted_priority_levels.flat_map do |level|
      data = levels_data.find { |d| d[:level] == level }
      (data ? data[:acts] : []).reject { |act| completed_ids.include?(act.id) }
    end
  end

  def last_attempt
    return @last_attempt if defined?(@last_attempt)

    @last_attempt =
      if completed_ids.any? && !filtered?
        QuizAttempt.where(user: user).order(submitted_at: :desc).first
      end
  end

  # Alternar o suporte de uma atividade para a seguinte: três exercícios de
  # texto em sequência cansam mais que os mesmos três intercalados com áudio.
  def support_of(activity, attached_names)
    names = attached_names[activity.id] || []

    if names.include?('image_file') ||
       (activity.media_url.present? && !activity.media_url.match?(/youtube\.com|youtu\.be/))
      :imagem
    elsif names.include?('video_file') || activity.video_url.present?
      :video
    elsif names.include?('audio_file')
      :audio
    else
      :texto
    end
  end

  def last_support
    return @last_support if defined?(@last_support)

    @last_support =
      if last_attempt&.activity_id
        support_of(last_attempt.activity, attachment_names_for([last_attempt.activity_id]))
      end
  end

  def best_candidate
    return @best_candidate if defined?(@best_candidate)

    @best_candidate =
      if last_support && pending_activities.any?
        names = attachment_names_for(pending_activities.map(&:id))
        pending_activities.find { |act| support_of(act, names) != last_support } ||
          pending_activities.first
      else
        pending_activities.first
      end
  end

  # Uma consulta só para todas as atividades candidatas, em vez de uma por
  # atividade ao perguntar o suporte de cada uma.
  def attachment_names_for(ids)
    return {} if ids.blank?

    ActiveStorage::Attachment
      .where(record_type: 'Activity', record_id: ids, name: MEDIA_ATTACHMENTS)
      .group_by(&:record_id)
      .transform_values { |records| records.map(&:name) }
  end

  def load_with_media(activity_id)
    Activity.with_attached_image_file
            .with_attached_video_file
            .with_attached_audio_file
            .includes(:teacher)
            .find(activity_id)
  end
end
