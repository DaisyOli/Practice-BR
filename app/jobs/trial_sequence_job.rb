# Roda uma vez por dia (cron do GoodJob, ver config/environments/production.rb).
#
# A sequência de emails de quem está testando. Existe por causa de uma medição de
# 2026-08-01: das 5 pessoas reais que tinham entrado no teste, 4 nunca
# responderam UMA questão — e a plataforma mandava um único email, no 3º dia,
# dizendo "continue praticando" para quem nunca praticou. Depois que o teste
# vencia, silêncio: o próximo email possível era o aviso de exclusão de conta,
# 11 meses depois.
#
# Três momentos, um email cada, no máximo três na vida da pessoa:
#
#   D+1 sem ter começado          → ativação (TrialMailer#activation_email)
#   fim do teste (esgotou/venceu) → fim (TrialMailer#ended_email)
#   +5 dias                       → volta (TrialMailer#winback_email)
#
# O lembrete do 3º dia (TrialReminderJob) continua existindo e agora só fala com
# quem COMEÇOU — os dois não se cruzam.
class TrialSequenceJob < ApplicationJob
  queue_as :default

  ACTIVATION_AFTER = 1.day
  WINBACK_AFTER    = 5.days

  def perform
    candidates.find_each do |trial|
      # No máximo um email por pessoa por rodada. Sem isto, alguém que esgotou o
      # teste no primeiro dia receberia dois emails na mesma manhã.
      send_activation(trial) || send_ended(trial) || send_winback(trial)
    end
  end

  private

  # `never_converted_trial?` em vez do papel sozinho: quem cancela a assinatura
  # VOLTA a ser trial, com o trial_expires_at do teste original de meses atrás.
  # Sem este filtro, um ex-aluno pagante receberia a sequência de boas-vindas do
  # teste no dia seguinte ao cancelamento.
  def candidates
    User.trials.where(stripe_customer_id: nil)
  end

  def send_activation(trial)
    return false if trial.activation_nudge_sent_at.present?
    return false unless trial.trial_access_active?
    return false unless trial.trial_activities_used.to_i.zero?
    return false if trial.created_at > ACTIVATION_AFTER.ago

    activity = first_activity_for(trial)
    return false if activity.nil?

    TrialMailer.activation_email(trial, activity).deliver_later
    trial.update_column(:activation_nudge_sent_at, Time.current)
    true
  end

  def send_ended(trial)
    return false if trial.trial_ended_email_sent_at.present?
    return false if trial.trial_access_active?

    TrialMailer.ended_email(trial, total_activities_for(trial)).deliver_later
    trial.update_column(:trial_ended_email_sent_at, Time.current)
    true
  end

  def send_winback(trial)
    return false if trial.trial_winback_sent_at.present?
    return false if trial.trial_ended_email_sent_at.blank?
    return false if trial.trial_ended_email_sent_at > WINBACK_AFTER.ago

    activity = first_activity_for(trial)
    return false if activity.nil?

    TrialMailer.winback_email(trial, activity).deliver_later
    trial.update_column(:trial_winback_sent_at, Time.current)
    true
  end

  # A atividade que vai no email. Só do nível declarado: durante o teste é o
  # único que abre, e mandar alguém para uma porta trancada seria pior que não
  # mandar nada.
  def first_activity_for(trial)
    return nil if trial.level.blank?

    feitas = QuizAttempt.where(user_id: trial.id).pluck(:activity_id)
    Activity.published
            .where(level: trial.level)
            .where.not(id: feitas)
            .order(created_at: :desc)
            .first
  end

  # Quantas atividades a assinatura abriria pra essa pessoa. Número concreto no
  # email do fim do teste: "foi uma porta de entrada, tem 145 do outro lado".
  def total_activities_for(trial)
    return 0 if trial.level.blank?

    Activity.published.where(level: trial.accessible_levels).count
  end
end
