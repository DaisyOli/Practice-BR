# Uma abertura da página do quiz por um aluno (ponto 2.1, 17/11/2026): até qual
# passo ele chegou, se começou a responder e se enviou. Quem abandona no meio
# não gera QuizAttempt; é aqui que esse abandono aparece.
#
# O navegador avisa (quiz_visit_controller.js) e o servidor só aceita o que faz
# sentido: o passo nunca volta, nunca passa do total, e o total é contado aqui,
# não no navegador.
class ActivityVisit < ApplicationRecord
  TOKEN = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/

  belongs_to :user
  belongs_to :activity

  # Cria a linha na primeira vez e depois só avança. `step` vazio não mexe no
  # passo (é o caso do envio).
  def self.record!(user:, activity:, token:, step: nil, answered: false, submitted: false)
    return unless token.to_s.match?(TOKEN)

    # Busca primeiro: só o primeiro aviso cria. O create_or_find_by cobre dois
    # avisos chegando juntos (o toque e o "Próxima" saem quase ao mesmo tempo).
    visit = find_by(token: token) || create_or_find_by!(token: token) do |nova|
      nova.user        = user
      nova.activity    = activity
      nova.total_steps = [activity.quiz_step_count, 1].max
    end
    # Token de outra pessoa ou de outra atividade: não mexe.
    return unless visit.user_id == user.id && visit.activity_id == activity.id

    now  = Time.current
    rows = where(id: visit.id)
    if step.present?
      passo = step.to_i.clamp(1, visit.total_steps)
      rows.update_all(["furthest_step = GREATEST(furthest_step, ?), updated_at = ?", passo, now])
    end
    rows.where(answered_at: nil).update_all(answered_at: now, updated_at: now)   if answered
    rows.where(submitted_at: nil).update_all(submitted_at: now, updated_at: now) if submitted
    visit
  end
end
