# O funil do teste, contado a partir do que o banco já guarda — sem tabela de
# eventos nem ferramenta de analytics.
#
#   pediu o teste       → conta criada pela API da landing (trial_expires_at, sem
#                         convite de professora)
#   usou o link         → trial_start_used_at. Mostra que o link foi consumido,
#                         não que a pessoa viu a dashboard.
#   interagiu no app    → first_human_at: toque, tecla ou rolagem
#   interagiu na atividade → first_activity_human_at
#   começou a responder → first_answer_at
#   concluiu a primeira → primeira QuizAttempt
#   venceu sem nada     → prazo passado, nenhuma tentativa, nunca pagou
#
# Por que não usar first_access_at e first_activity_opened_at: eles são gravados
# quando a página é pedida ao servidor, e o antivírus de email que segue o link
# do botão também pede a página. E, nas contas anteriores a 14/10/2026, o
# first_access_at foi copiado do uso do link.
#
# Os três sinais de pessoa só existem nas contas criadas desde `measured_since`,
# então esses degraus contam só essas contas (`measured`).
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

  # O dia em que os sinais de pessoa entraram em produção.
  def self.measured_since
    Time.zone.local(2026, 11, 3)
  end

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
    measured  = users.select { |u| u.created_at >= self.class.measured_since }

    {
      requested:          users.size,
      link_used:          users.count { |u| u.trial_start_used_at },
      measured:           measured.size,
      entered:            measured.count { |u| u.first_human_at || first_attempts[u.id] },
      opened_activity:    measured.count { |u| u.first_activity_human_at || first_attempts[u.id] },
      answered:           measured.count { |u| u.first_answer_at || first_attempts[u.id] },
      by_source:          measured.filter_map(&:first_entry_source).tally,
      completed_first:    activated.size,
      expired_untouched:  users.count { |u| expired_untouched?(u, first_attempts) },
      converted:          users.count { |u| u.stripe_customer_id.present? },
      activation_rate:    users.empty? ? 0.0 : (activated.size * 100.0 / users.size).round(1),
      activated_after:    activated.group_by { |u| last_nudge_before(u, first_attempts[u.id], recoveries) }
                                   .transform_values(&:size)
    }
  end

  private

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
