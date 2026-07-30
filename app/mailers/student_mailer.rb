class StudentMailer < ApplicationMailer
  CEFR_LEVELS = User::CEFR_LEVELS

  def new_activity(student, activity)
    @student  = student
    @activity = activity
    @url      = activity_url(activity)
    @lang     = student.language.presence || "pt"

    subject = case @lang
              when "fr" then "Nouvel exercice · exercício novo pour vous 📚"
              when "en" then "New exercise · exercício novo for you 📚"
              else           "Exercício novo no seu nível, #{student.name} 📚"
              end

    mail(to: student.email, subject: subject)
  end

  def weekly_reminder(student, activities, featured = [])
    @student    = student
    @activities = activities
    @featured   = featured
    @url        = student_dashboard_url
    @lang       = student.language.presence || "pt"

    subject = case @lang
              when "fr" then "Vos exercices · seus exercícios de la semaine 🌿"
              when "en" then "Your exercises · seus exercícios this week 🌿"
              else           "Seus exercícios desta semana, #{student.name} 🌿"
              end

    mail(to: student.email, subject: subject)
  end

  # Cartão recusado. Este email é o que dá sentido à tolerância: sem ele o aluno
  # não sabe que precisa agir e a tolerância só adia a surpresa.
  def payment_failed(student)
    @student   = student
    @days_left = student.payment_grace_days_left || User::PAYMENT_GRACE_DAYS
    @url       = billing_update_payment_url
    @lang      = student.language.presence || "pt"

    subject = case @lang
              when "fr" then "Problème de paiement · problema no pagamento 💳"
              when "en" then "Payment problem · problema no pagamento 💳"
              else           "Tivemos um problema com seu pagamento 💳"
              end

    mail(to: student.email, subject: subject)
  end

  # Levels that should receive a notification when an activity of `level` is published.
  # A B1 activity notifies B1 and B2 students (their level and one above).
  def self.notifiable_levels_for_activity(level)
    idx = CEFR_LEVELS.index(level)
    return [] unless idx
    next_level = CEFR_LEVELS[idx + 1]
    next_level ? [level, next_level] : [level]
  end
end
