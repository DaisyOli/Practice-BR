# Roda toda segunda-feira (cron do GoodJob, ver config/environments/production.rb).
# Nunca esteve de fato agendado: só existia como rake task pensada para o
# Heroku Scheduler, que nunca foi configurado lá (só o ping de keep-alive do
# Postgres está registrado). Substitui lib/tasks/student_emails.rake.
class WeeklyReminderJob < ApplicationJob
  queue_as :default

  # Teto de atividades no email. Antes não havia nenhum: quem estava há semanas
  # sem entrar recebia a lista inteira do nível, e uma lista longa não convida —
  # intimida. Cinco é o que cabe numa tela de telefone sem rolar, e o que parece
  # "dá pra fazer" em vez de "estou atrasado".
  #
  # Casa com o bloco de `featured` abaixo, que só entra quando há menos de 3
  # pendentes e traz até 3: o máximo continua sendo 5 pelos dois caminhos.
  MAX_ACTIVITIES = 5

  def perform
    return unless Date.current.monday?

    # Sem filtro de `subscription_status`, e é decisão, não esquecimento (03/08/2026).
    # Quem está em `canceling` cancelou a RENOVAÇÃO, mas pagou até o fim do período
    # e continua com acesso — cortar o lembrete seria encurtar o que a pessoa já
    # comprou. Quem de fato saiu vira `trial` no handle_subscription_deleted e cai
    # fora deste `where` sozinho.
    User.where(role: "student", weekly_reminder_email: true).find_each do |student|
      next if student.level.blank?

      levels = StudentMailer.notifiable_levels_for_activity(student.level)
                             .push(student.level)
                             .uniq

      completed_ids = QuizAttempt.where(user_id: student.id).pluck(:activity_id)

      pending = Activity.published
                         .where(level: levels)
                         .where.not(id: completed_ids)
                         .order(created_at: :desc)
                         .limit(MAX_ACTIVITIES)
                         .to_a

      featured = []
      if pending.count < 3
        featured = Activity.published
                            .where(level: levels)
                            .joins(:activity_ratings)
                            .group("activities.id")
                            .having("COUNT(activity_ratings.id) >= 1")
                            .order("AVG(activity_ratings.stars) DESC")
                            .where.not(id: completed_ids + pending.map(&:id))
                            .limit(3)
                            .to_a
      end

      next if pending.empty? && featured.empty?

      StudentMailer.weekly_reminder(student, pending, featured).deliver_later

      push_body = case student.language
                  when "fr" then "Vos exercices de la semaine vous attendent 🌿"
                  when "en" then "Your exercises for this week are ready 🌿"
                  else           "Seus exercícios desta semana estão esperando 🌿"
                  end

      PushNotificationService.send_to_user(
        student,
        title: "Practice-BR",
        body:  push_body,
        url:   Rails.application.routes.url_helpers.student_dashboard_url(
                 host: Rails.application.config.action_mailer.default_url_options[:host]
               )
      )
    end
  end
end
