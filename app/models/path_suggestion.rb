# Uma proposta do agente do percurso (LevelPathAgent) esperando a Daisy.
# Ver a migration CreatePathSuggestionsAndActivityTheme.
class PathSuggestion < ApplicationRecord
  KINDS    = %w[full new_activity].freeze
  STATUSES = %w[queued running done failed].freeze

  belongs_to :activity, optional: true

  validates :level,  inclusion: { in: User::CEFR_LEVELS }
  validates :kind,   inclusion: { in: KINDS }
  validates :status, inclusion: { in: STATUSES }

  scope :working,    -> { where(status: %w[queued running]) }
  scope :unresolved, -> { where(resolved_at: nil) }
  # O que aparece na tela: pronto, ainda sem decisão — e, para atividade nova,
  # só quando o agente acha que ela entra (as "fica fora" não pedem nada).
  scope :to_review,  -> { unresolved.where(status: "done") }

  def working? = status.in?(%w[queued running])

  def proposes_change?
    kind == "full" || payload["decision"].in?(%w[insert replace])
  end

  def resolve!(resolution)
    update!(resolution: resolution, resolved_at: Time.current)
  end

  # Pede uma avaliação quando uma atividade é publicada. Não repete para a
  # mesma atividade, e não pede se ela já está no percurso.
  #
  # Só liga onde `config.x.level_path_on_publish` está ligado — produção. Em
  # desenvolvimento, semear ou publicar atividades chamaria a API paga a cada
  # publicação; nos testes, quem quer o comportamento liga explicitamente.
  def self.request_for_new!(activity)
    return unless Rails.configuration.x.level_path_on_publish
    return if activity.path_position.present?
    return if where(kind: "new_activity", activity_id: activity.id).exists?

    suggestion = create!(kind: "new_activity", level: activity.level, activity: activity)
    LevelPathJob.perform_later(suggestion.id)
    suggestion
  end
end
