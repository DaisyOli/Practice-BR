# O funil do teste, contado a partir do que o banco já guarda — sem tabela de
# eventos nem ferramenta de analytics. Cada degrau é uma coluna ou um fato:
#
#   pediu o teste        → conta criada pela API da landing (trial_expires_at,
#                          sem convite de professora)
#   entrou na plataforma → first_access_at (ou trial_start_used_at / senha, para
#                          contas anteriores a 2026-10-14)
#   abriu uma atividade  → first_activity_opened_at (só existe a partir de
#                          2026-10-14 — antes disso o degrau fica subcontado)
#   concluiu a primeira  → primeira QuizAttempt
#   venceu sem nada      → prazo passado, nenhuma tentativa, nunca pagou
#
# "Ativou depois de um lembrete" quer dizer só isso: a primeira atividade veio
# depois de um email. Não prova que o email causou nada — a pessoa podia voltar
# de qualquer jeito. Com amostras de poucas pessoas, ler como pista, não como
# resultado.
class TrialFunnel
  # Os emails que contam como "lembrete", na ordem em que costumam sair.
  NUDGES = {
    "mesmo dia (4h)" => :first_nudge_sent_at,
    "D+1"            => :activation_nudge_sent_at,
    "reabertura"     => :trial_reopened_at
  }.freeze

  def initialize(from:, to: Time.current, exclude_ids: [])
    @from        = from
    @to          = to
    @exclude_ids = exclude_ids.map(&:to_i)
  end

  def cohort
    User.where.not(trial_expires_at: nil)
        .where(invitation_created_at: nil)
        .where(created_at: @from..@to)
        .where.not(id: @exclude_ids)
  end

  def stats
    users          = cohort.to_a
    first_attempts = QuizAttempt.where(user_id: users.map(&:id)).group(:user_id).minimum(:created_at)
    recoveries     = TrialEvent.where(user_id: users.map(&:id), kind: "recovery_email")
                               .pluck(:user_id, :created_at).to_h

    activated = users.select { |u| first_attempts[u.id] }

    {
      requested:          users.size,
      accessed:           users.count { |u| accessed?(u) },
      opened_activity:    users.count { |u| u.first_activity_opened_at || first_attempts[u.id] },
      completed_first:    activated.size,
      expired_untouched:  users.count { |u| expired_untouched?(u, first_attempts) },
      converted:          users.count { |u| u.stripe_customer_id.present? },
      activation_rate:    users.empty? ? 0.0 : (activated.size * 100.0 / users.size).round(1),
      activated_after:    activated.group_by { |u| last_nudge_before(u, first_attempts[u.id], recoveries) }
                                   .transform_values(&:size)
    }
  end

  private

  def accessed?(user)
    user.first_access_at || user.trial_start_used_at || user.password_set_at
  end

  def expired_untouched?(user, first_attempts)
    user.trial? && user.stripe_customer_id.blank? && first_attempts[user.id].nil? &&
      user.trial_expires_at < Time.current
  end

  # O último email antes da primeira atividade — ou "nenhum lembrete", se ela
  # veio antes de qualquer um.
  def last_nudge_before(user, first_attempt_at, recoveries)
    sent = NUDGES.map { |label, col| [label, user.public_send(col)] }
    sent << ["recuperação manual", recoveries[user.id]]
    sent = sent.select { |_, at| at && at < first_attempt_at }

    sent.max_by { |_, at| at }&.first || "nenhum lembrete"
  end
end
