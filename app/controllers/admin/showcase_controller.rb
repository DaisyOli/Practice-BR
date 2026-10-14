module Admin
  # A Vitrine do teste: a Daisy escolhe, por nível, as 3 atividades que quem
  # chega pelo teste encontra primeiro — no "Comece por aqui", nos emails e no
  # cartão de próxima atividade (User#suggested_first_activity).
  #
  # Existe porque, sem escolha, a vitrine era "a mais recente publicada": podia
  # ser a mais longa, a mais difícil ou a menos bonita do catálogo. O teste é o
  # primeiro contato com a plataforma, e quem melhor escolhe é a professora.
  class ShowcaseController < BaseController
    def index
      @levels = User::CEFR_LEVELS.map do |level|
        activities = Activity.published.where(level: level).order(:title).to_a
        {
          level:      level,
          activities: activities,
          chosen:     Activity.published.where(level: level).in_trial_showcase.to_a,
          fallback:   Activity.published.where(level: level).order(created_at: :desc).first
        }
      end
      @traits = traits_for(@levels.flat_map { |l| l[:activities] })
    end

    # Recebe showcase[NÍVEL][POSIÇÃO] = id. Refaz o nível inteiro numa
    # transação: limpa e grava de novo, para nunca esbarrar no índice único no
    # meio de uma troca de posições.
    def update
      choices = params.fetch(:showcase, {}).permit!.to_h

      Activity.transaction do
        User::CEFR_LEVELS.each do |level|
          Activity.where(level: level).where.not(trial_showcase_position: nil)
                  .update_all(trial_showcase_position: nil)

          ids = (1..Activity::TRIAL_SHOWCASE_SLOTS)
                  .map { |pos| choices.dig(level, pos.to_s).presence&.to_i }
                  .compact.uniq

          ids.each.with_index(1) do |id, position|
            Activity.published.where(level: level, id: id)
                    .update_all(trial_showcase_position: position)
          end
        end
      end

      redirect_to admin_showcase_path, notice: "Vitrine salva 🌱"
    end

    private

    # O que ajuda a escolher, ao lado de cada título: tem questão aberta (a
    # correção da IA é o que mais impressiona no teste), tem mídia, quantas
    # questões, e a nota dos alunos.
    def traits_for(activities)
      ids        = activities.map(&:id)
      open_ended = Question.where(activity_id: ids, question_type: "open_ended").distinct.pluck(:activity_id).to_set
      questions  = Question.where(activity_id: ids).group(:activity_id).count
      media      = ActiveStorage::Attachment.where(record_type: "Activity", record_id: ids,
                                                   name: %w[video_file audio_file])
                                            .pluck(:record_id, :name).to_h
      ratings    = ActivityRating.where(activity_id: ids).group(:activity_id).average(:stars)

      activities.to_h do |a|
        tags = []
        tags << "✍️ aberta" if open_ended.include?(a.id)
        tags << "🎬 vídeo"  if media[a.id] == "video_file" || a.video_url.present?
        tags << "🎧 áudio"  if media[a.id] == "audio_file"
        tags << "#{questions[a.id].to_i} questões"
        tags << "⭐ #{ratings[a.id].to_f.round(1)}" if ratings[a.id]
        [a.id, tags.join(" · ")]
      end
    end
  end
end
