module Admin
  # O percurso do nível: a Daisy escolhe, por nível, até 10 atividades na ordem
  # em que quem chega deve fazê-las — do mais simples ao mais exigente. As 3
  # primeiras são a vitrine do teste.
  #
  # Começou como a "Vitrine do teste" (3 posições): sem escolha, quem chegava
  # recebia "a mais recente publicada", que podia ser a mais longa ou a mais
  # difícil do nível. Virou percurso porque o mesmo problema vale para o aluno
  # que assina: um A1 iniciante não deveria cair numa atividade de fim de nível.
  # A ordem vale por trás (User#next_path_activity), sem nada visível ao aluno.
  class PathController < BaseController
    def index
      @levels = User::CEFR_LEVELS.map do |level|
        activities = Activity.published.where(level: level).order(:title).to_a
        {
          level:      level,
          activities: activities,
          chosen:     Activity.published.where(level: level).in_path.to_a,
          fallback:   Activity.published.where(level: level).order(created_at: :desc).first,
          working:    PathSuggestion.where(level: level, kind: "full").working.exists?,
          # A última proposta completa ainda sem decisão: pré-preenche a tela.
          proposal:   PathSuggestion.where(level: level, kind: "full").to_review.order(:created_at).last,
          failed:     PathSuggestion.where(level: level, kind: "full").unresolved
                                    .where(status: "failed").order(:created_at).last
        }
      end
      @traits = traits_for(@levels.flat_map { |l| l[:activities] })
      @new_activity_suggestions = PathSuggestion.where(kind: "new_activity").to_review
                                                .includes(:activity).order(:created_at)
                                                .select(&:proposes_change?)
      @working_any = @levels.any? { |l| l[:working] }
    end

    # Recebe path[NÍVEL][POSIÇÃO] = id e themes[ID] = tema. Salvar é a
    # aprovação: as propostas completas que estavam na tela ficam resolvidas.
    def update
      choices = params.fetch(:path, {}).permit!.to_h

      Activity.transaction do
        User::CEFR_LEVELS.each do |level|
          ids = (1..Activity::PATH_SLOTS).map { |pos| choices.dig(level, pos.to_s).presence }.compact
          Activity.set_path!(level, ids)
        end
        save_themes(params.fetch(:themes, {}).permit!.to_h)
        PathSuggestion.where(kind: "full").to_review.find_each { |s| s.resolve!("saved") }
      end

      redirect_to admin_path_path, notice: "Percurso salvo 🌱"
    end

    # "✨ Sugerir com o agente" de um nível. Não pede de novo enquanto o agente
    # ainda está trabalhando nesse nível.
    def suggest
      level = params[:level].to_s
      return redirect_to(admin_path_path, alert: "Nível desconhecido.") unless level.in?(User::CEFR_LEVELS)

      unless PathSuggestion.where(level: level, kind: "full").working.exists?
        PathSuggestion.where(level: level, kind: "full").unresolved.find_each { |s| s.resolve!("replaced") }
        suggestion = PathSuggestion.create!(level: level, kind: "full")
        LevelPathJob.perform_later(suggestion.id)
      end

      redirect_to admin_path_path(anchor: "nivel-#{level}"),
                  notice: "O agente está lendo as atividades do #{level} ☕ — a página atualiza sozinha."
    end

    # Aceitar a sugestão de uma atividade nova: entra na posição proposta.
    def accept
      suggestion = PathSuggestion.where(kind: "new_activity").to_review.find(params[:id])
      activity   = suggestion.activity
      return ignore_with(suggestion, "A atividade não está mais publicada.") unless activity && !activity.draft?

      ids = Activity.published.where(level: suggestion.level).in_path.pluck(:id) - [activity.id]
      position = suggestion.payload["position"].to_i
      if suggestion.payload["decision"] == "replace"
        ids[position - 1] = activity.id
      else
        ids.insert(position - 1, activity.id)
      end

      Activity.transaction do
        Activity.set_path!(suggestion.level, ids.compact)
        suggestion.resolve!("accepted")
      end
      redirect_to admin_path_path(anchor: "nivel-#{suggestion.level}"),
                  notice: "\"#{activity.title}\" entrou no percurso do #{suggestion.level} 🌱"
    end

    # Ignorar (atividade nova) ou descartar (proposta completa).
    def dismiss
      suggestion = PathSuggestion.unresolved.find(params[:id])
      suggestion.resolve!("ignored")
      redirect_to admin_path_path(anchor: "nivel-#{suggestion.level}")
    end

    private

    def ignore_with(suggestion, message)
      suggestion.resolve!("ignored")
      redirect_to admin_path_path, alert: message
    end

    # Só grava o que mudou; tema em branco apaga.
    def save_themes(themes)
      Activity.where(id: themes.keys).find_each do |activity|
        theme = themes[activity.id.to_s].to_s.strip.first(40).presence
        activity.update_column(:theme, theme) if theme != activity.theme
      end
    end

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
