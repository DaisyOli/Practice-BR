class AdminMailer < ApplicationMailer
  ADMIN_EMAIL = "contato@practicebr.com".freeze
  DAISY_EMAIL = "daisy.oliani@gmail.com".freeze

  def new_teacher_notification(teacher)
    @teacher = teacher
    mail(to: ADMIN_EMAIL, subject: "Novo professor na Practice-BR: #{teacher.display_name}")
  end

  def draft_ready(activity)
    @activity = activity
    @exercise_count = activity.questions.count +
                      activity.sentence_orderings.count +
                      activity.paragraph_orderings.count +
                      activity.column_matchings.count
    @review_url = review_draft_activity_url(
      activity,
      host: "app.practicebr.com",
      protocol: "https"
    )
    mail(to: DAISY_EMAIL, subject: "✅ Nova atividade #{activity.level} pronta para revisão — #{activity.title}")
  end

  # Antes, falha de pagamento só existia como uma linha de log — ninguém era
  # avisado, e o aluno seguia com acesso enquanto o Stripe tentava o cartão.
  def payment_failed_notification(student)
    @student   = student
    @days_left = student.payment_grace_days_left || User::PAYMENT_GRACE_DAYS
    mail(to: DAISY_EMAIL, subject: "💳 Falha de pagamento — #{student.display_name}")
  end

  def draft_generation_failed(level, error_key)
    @level = level
    @error_key = error_key
    @generate_url = "https://app.practicebr.com/activities/generate_with_ai"
    mail(to: DAISY_EMAIL, subject: "⚠️ Falha ao gerar atividade #{level} — Practice-BR")
  end
end
