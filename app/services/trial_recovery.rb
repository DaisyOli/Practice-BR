# Recuperação manual de trials: quem se cadastrou numa janela de datas e não fez
# nenhuma atividade recebe um email com um link que entra sem senha, direto
# numa atividade do nível — e, se o teste já venceu ou está a menos de 48h de
# vencer, ganha 48h de prazo.
#
# Duas etapas, de propósito separadas (lib/tasks/trial_recovery.rake):
#
#   TrialRecovery.new(from:, to:).report     → só lê. Lista todo mundo da janela,
#                                              elegível ou não, e por quê.
#   TrialRecovery.new(from:, to:).run!(ids)  → envia, mas só para os ids
#                                              aprovados que AINDA forem
#                                              elegíveis no momento do envio.
#
# Exigir os ids no envio é o que garante que sai exatamente a lista que a Daisy
# leu. Quem fez uma atividade entre a prévia e o envio cai fora sozinho.
#
# "Uma vez só" não depende de ninguém lembrar: o índice único de trial_events
# (user_id, kind) recusa o segundo registro, mesmo com duas execuções juntas.
class TrialRecovery
  # Abaixo disto de prazo restante, o teste é reaberto. Quanto ele ganha é
  # parâmetro (`extension:`): 48h na recuperação de 12–13/10, 7 dias na
  # campanha da base antiga — quem largou o teste há semanas não está
  # esperando o email, e 48h é pouco para ver e voltar.
  EXTENSION_THRESHOLD = 48.hours
  EXTENSION_KINDS     = %w[extension extension_48h].freeze

  Row = Struct.new(:user, :eligible, :reason, :welcome, :will_extend, keyword_init: true)

  # `from` e `to` são datas (inclusive) no fuso da aplicação — Paris
  # (config.time_zone). 12/10 começa à meia-noite de Paris, não de Londres.
  def initialize(from:, to:, extension: 48.hours)
    @range     = Time.zone.parse(from.to_s).beginning_of_day..Time.zone.parse(to.to_s).end_of_day
    @extension = extension
  end

  attr_reader :range, :extension

  def report
    users_in_window.map do |user|
      reason = ineligibility_reason(user)
      Row.new(
        user:        user,
        eligible:    reason.nil?,
        reason:      reason,
        welcome:     welcome_delivery_status(user),
        will_extend: reason.nil? && extension_due?(user)
      )
    end
  end

  # Devolve { sent: [ids], skipped: { id => motivo } }.
  def run!(approved_ids)
    approved = approved_ids.map(&:to_i).to_set
    result   = { sent: [], skipped: {} }

    users_in_window.where(id: approved.to_a).each do |user|
      reason = ineligibility_reason(user)
      if reason
        result[:skipped][user.id] = reason
        next
      end

      recover(user) ? result[:sent] << user.id : result[:skipped][user.id] = "já recuperado"
    end

    (approved - users_in_window.where(id: approved.to_a).pluck(:id)).each do |id|
      result[:skipped][id] = "fora da janela de datas"
    end

    result
  end

  private

  def users_in_window
    User.where(created_at: range).order(:created_at)
  end

  # nil = elegível. Senão, a frase que aparece na prévia.
  def ineligibility_reason(user)
    return "não é trial (papel: #{user.role})"            unless user.trial?
    return "já foi aluno pagante (tem cliente na Stripe)" if user.stripe_customer_id.present?
    return "convite de professora, não veio da landing"   if user.invitation_created_at.present?
    return "admin"                                        if user.admin?
    return "pediu para não receber emails"                if user.marketing_emails_opted_out?
    # Quem fez 1 ou 2 entra (com texto próprio). Quem fez as 3 terminou o teste
    # pelo número de atividades — mais prazo não muda nada; a conversa com essa
    # pessoa é sobre assinar.
    return "já fez as 3 atividades"                       if user.quiz_attempts.count >= 3
    return "já recebeu a recuperação"                     if user.trial_events.exists?(kind: "recovery_email")
    return "sem atividade publicada no nível #{user.level}" if user.suggested_first_activity.nil?

    nil
  end

  def extension_due?(user)
    user.trial_expires_at.nil? || user.trial_expires_at < EXTENSION_THRESHOLD.from_now
  end

  # Tudo numa transação: o registro de auditoria, a extensão e o email na fila
  # (o GoodJob grava a fila no mesmo Postgres). Ou acontece tudo, ou nada.
  def recover(user)
    User.transaction do
      activity = user.suggested_first_activity
      extended = false

      TrialEvent.create!(user: user, kind: "recovery_email",
                         details: { "window" => [range.begin.to_date, range.end.to_date].map(&:iso8601),
                                    "activity_id" => activity.id })

      if extension_due?(user) && !user.trial_events.exists?(kind: EXTENSION_KINDS)
        before = user.trial_expires_at
        after  = extension.from_now
        user.update_columns(trial_expires_at: after)
        TrialEvent.create!(user: user, kind: "extension",
                           details: { "from" => before&.iso8601, "to" => after.iso8601,
                                      "hours" => (extension / 1.hour).round })
        extended = true
      end

      # Este email faz o papel dos lembretes automáticos (mesmo dia, D+1 e o do
      # 3º dia de quem começou). Marcar os três impede a sequência de mandar
      # mais um logo em seguida.
      now = Time.current
      user.update_columns(first_nudge_sent_at:      user.first_nudge_sent_at || now,
                          activation_nudge_sent_at: user.activation_nudge_sent_at || now,
                          trial_reminder_sent_at:   user.trial_reminder_sent_at || now)

      TrialMailer.recovery_email(user, activity, extended: extended).deliver_later
      true
    end
  rescue ActiveRecord::RecordNotUnique
    false
  end

  # O email de boas-vindas saiu? A fonte é a própria fila: o GoodJob guarda os
  # jobs terminados (14 dias, padrão da gem), com erro se houve. Entrega na
  # caixa da pessoa (bounce, spam) fica no painel do Resend — daqui não se vê.
  def welcome_delivery_status(user)
    job = GoodJob::Job
            .where("serialized_params->>'job_class' = 'ActionMailer::MailDeliveryJob'")
            .where("serialized_params->'arguments'->>0 = 'TrialMailer'")
            .where("serialized_params->'arguments'->>1 = 'welcome_email'")
            .where("serialized_params::text LIKE ?", "%/User/#{user.id}\"%")
            .order(:created_at).last
    return "sem registro na fila" if job.nil?
    return "falhou: #{job.error.to_s.truncate(80)}" if job.error.present? && job.finished_at.present?
    return "enviado #{job.finished_at.strftime('%d/%m %H:%M')}" if job.finished_at.present?

    "na fila"
  end
end
