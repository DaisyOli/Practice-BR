# Roda a cada 6h (cron do GoodJob, ver config/environments/production.rb).
# Avisa quem já praticou antes e sumiu por 48h+.
#
# Até 2026-08-01 este job só mandava push — e a base tinha ZERO inscrições de
# push, então ele rodava a cada 6 horas olhando pra uma lista vazia. O alerta
# existia no código e não existia na vida de ninguém: alunos passavam uma semana
# fora sem receber nada. Agora o email é o canal principal (é o que comprovada-
# mente chega) e o push continua junto, pra quem um dia ativar.
#
# inactivity_nudge_sent_at garante um único aviso por ausência: só dispara de
# novo depois que o aluno volta a praticar. Não se aplica a trials, que têm o
# TrialReminderJob.
class InactivityNudgeJob < ApplicationJob
  queue_as :default

  ABSENCE = 48.hours

  def perform
    candidates.find_each do |student|
      last_activity_at = student.quiz_attempts.maximum(:submitted_at)
      next if last_activity_at.nil? || last_activity_at > ABSENCE.ago
      next if student.inactivity_nudge_sent_at.present? && student.inactivity_nudge_sent_at >= last_activity_at

      # Sem nada pendente, o convite levaria a pessoa a uma tela vazia — pior
      # que silêncio. Mesma regra do WeeklyReminderJob.
      suggestion = next_activity_for(student)
      next if suggestion.nil?

      StudentMailer.inactivity_nudge(student, suggestion).deliver_later

      title, body = copy_for(student.language)
      PushNotificationService.send_to_user(
        student,
        title: title,
        body:  body,
        url:   Rails.application.routes.url_helpers.student_dashboard_url(
                 host: Rails.application.config.action_mailer.default_url_options[:host]
               )
      )
      student.update_column(:inactivity_nudge_sent_at, Time.current)
    end
  end

  private

  # Um interruptor só: quem desligou o lembrete semanal na dashboard pediu pra
  # não ser lembrado, e o alerta de ausência é lembrete com outro nome.
  def candidates
    User.where(role: "student", weekly_reminder_email: true)
  end

  def next_activity_for(student)
    return nil if student.level.blank?

    done = QuizAttempt.where(user_id: student.id).pluck(:activity_id)
    Activity.published
            .where(level: student.accessible_levels)
            .where.not(id: done)
            .order(created_at: :desc)
            .first
  end

  def copy_for(language)
    case language
    when "fr" then ["Vous nous manquez · sentimos sua falta !", "Et si on pratiquait le portugais · português 5 minutes aujourd'hui ?"]
    when "en" then ["We miss you · sentimos sua falta!", "How about 5 minutes of Portuguese · português today?"]
    else           ["Sentimos sua falta!", "Que tal 5 minutinhos de português hoje?"]
    end
  end
end
