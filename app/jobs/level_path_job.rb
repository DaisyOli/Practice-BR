# Roda o agente do percurso em segundo plano (a chamada leva de 30s a 2min, e o
# Heroku corta a requisição em 30s). O resultado fica na PathSuggestion, que a
# tela Admin › Percurso mostra para a Daisy aprovar.
class LevelPathJob < ApplicationJob
  queue_as :default

  def perform(suggestion_id)
    suggestion = PathSuggestion.find_by(id: suggestion_id)
    # Só começa o que está na fila: uma segunda execução do mesmo job (o
    # GoodJob pode repetir) não chama a IA de novo.
    return unless suggestion && PathSuggestion.where(id: suggestion.id, status: "queued")
                                              .update_all(status: "running") == 1

    agent   = LevelPathAgent.new
    payload =
      if suggestion.kind == "full"
        agent.suggest_path(suggestion.level)
      else
        return suggestion.update!(status: "failed", error_message: "A atividade foi apagada.") unless suggestion.activity

        result = agent.evaluate(suggestion.activity)
        # O tema é descrição, não decisão pedagógica: entra direto, e a Daisy
        # corrige na mesma tela se quiser. A posição no percurso, essa espera ela.
        suggestion.activity.update_column(:theme, result["theme"]) if result["theme"].present?
        result
      end

    suggestion.update!(status: "done", payload: payload)
  rescue LevelPathAgent::Failed => e
    suggestion&.update!(status: "failed", error_message: e.message)
  rescue Anthropic::Errors::APIError => e
    Rails.logger.error "[LevelPath] #{e.class}: #{e.message}"
    suggestion&.update!(status: "failed", error_message: "A IA não respondeu agora. Tente de novo em alguns minutos.")
  rescue StandardError => e
    # Resposta num formato inesperado não pode deixar a sugestão presa em
    # "running" para sempre — a tela ficaria atualizando sem fim.
    Rails.logger.error "[LevelPath] #{e.class}: #{e.message}"
    Sentry.capture_exception(e)
    suggestion&.update!(status: "failed", error_message: "Algo deu errado do nosso lado. Tente de novo.")
  end
end
