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

  # Boas-vindas de quem acabou de pagar. Faz dois trabalhos num email só:
  #
  # 1. Diz o que mudou. A assinatura só vale o preço se a pessoa souber o que
  #    ganhou — antes disto ela saía do Stripe e nada explicava a diferença.
  # 2. É a segunda chance de criar a senha, pra quem pulou o formulário da tela
  #    de sucesso. O bloco só aparece quando ainda não há senha (`password_token`
  #    vem nulo nos outros casos, ver WebhooksController).
  SUBSCRIPTION_WELCOME = {
    "fr" => {
      subject:   "Bienvenue · bem-vindo dans Practice-BR 🎉",
      hello:     "Bonjour",
      title:     "Votre accès complet est ouvert",
      lead:      "Merci de votre confiance. À partir d'aujourd'hui, la pratique quotidienne ne dépend plus que de vous — le reste, c'est notre travail.",
      includes:  "Ce que vous avez maintenant",
      i1:        "Toutes les activités jusqu'à votre niveau",
      i2:        "Jusqu'à 5 activités par jour",
      i3:        "Les niveaux précédents, à revoir quand vous voulez",
      i4:        "Correction automatique et détaillée, à chaque exercice",
      cta:       "Commencer une activité →",
      pwd_title: "Il vous manque un mot de passe",
      pwd_lead:  "Vous êtes entré sans en créer un — c'était voulu. Ce lien vous en fait un, et c'est ce qui vous ramènera à votre compte plus tard.",
      pwd_cta:   "Créer mon mot de passe",
      manage:    "Vous pouvez annuler quand vous voulez depuis votre tableau de bord.",
      footer:    "Une question ? Répondez à cet email, on vous lit."
    },
    "en" => {
      subject:   "Welcome · bem-vindo to Practice-BR 🎉",
      hello:     "Hi",
      title:     "Your full access is open",
      lead:      "Thank you for trusting us. From today on, daily practice is up to you — the rest is our job.",
      includes:  "What you have now",
      i1:        "All activities up to your level",
      i2:        "Up to 5 activities a day",
      i3:        "Previous levels, to review whenever you want",
      i4:        "Automatic, detailed correction on every exercise",
      cta:       "Start an activity →",
      pwd_title: "You're still missing a password",
      pwd_lead:  "You came in without creating one — that was on purpose. This link sets one up, and that's what brings you back to your account later.",
      pwd_cta:   "Create my password",
      manage:    "You can cancel whenever you want from your dashboard.",
      footer:    "Questions? Just reply to this email — we read them."
    },
    "pt" => {
      subject:   "Boas-vindas à Practice-BR 🎉",
      hello:     "Oi",
      title:     "Seu acesso completo está aberto",
      lead:      "Obrigada pela confiança. A partir de hoje a prática diária depende só de você — o resto é com a gente.",
      includes:  "O que você tem agora",
      i1:        "Todas as atividades até o seu nível",
      i2:        "Até 5 atividades por dia",
      i3:        "Os níveis anteriores, para revisar quando quiser",
      i4:        "Correção automática e detalhada em cada exercício",
      cta:       "Começar uma atividade →",
      pwd_title: "Falta a sua senha",
      pwd_lead:  "Você entrou sem criar uma — era essa a ideia. Este link cria a sua, e é ela que vai te trazer de volta à conta depois.",
      pwd_cta:   "Criar minha senha",
      manage:    "Você pode cancelar quando quiser pelo seu dashboard.",
      footer:    "Ficou com dúvida? Responda este email que a gente lê."
    }
  }.freeze

  def subscription_welcome(student, password_token = nil)
    @student      = student
    @lang         = student.language.presence || "pt"
    @copy         = SUBSCRIPTION_WELCOME.fetch(@lang, SUBSCRIPTION_WELCOME["fr"])
    @url          = student_dashboard_url
    @password_url = password_token.present? &&
                    edit_user_password_url(reset_password_token: password_token)

    mail(to: student.email, subject: @copy[:subject])
  end

  # 48h sem praticar. O tom aqui importa mais que em qualquer outro email da
  # plataforma: quem sumiu dois dias não fez nada de errado, e um email que soa
  # a cobrança é um email que ensina a pessoa a não abrir os próximos. Por isso
  # ele traz uma atividade concreta e curta, não uma lista de deveres.
  INACTIVITY = {
    "fr" => {
      subject: "On reprend · vamos voltar ? 🌱",
      title:   "Deux jours sans portugais, ça arrive",
      lead:    "La semaine passe vite. On vous a gardé une activité courte pour reprendre le fil — pas besoin de rattraper quoi que ce soit.",
      cta:     "Faire cette activité →",
      footer:  "Vous ne voulez plus de rappels ? Le bouton est sur votre tableau de bord."
    },
    "en" => {
      subject: "Let's pick it back up · vamos voltar? 🌱",
      title:   "Two days without Portuguese happens",
      lead:    "Weeks go by fast. We saved you one short activity to get back in — nothing to catch up on.",
      cta:     "Do this activity →",
      footer:  "Don't want reminders anymore? The button is on your dashboard."
    },
    "pt" => {
      subject: "Vamos voltar? 🌱",
      title:   "Dois dias sem português acontece",
      lead:    "A semana passa voando. Guardamos uma atividade curta pra você pegar o fio de novo — não tem nada pra recuperar.",
      cta:     "Fazer esta atividade →",
      footer:  "Não quer mais lembretes? O botão está no seu dashboard."
    }
  }.freeze

  def inactivity_nudge(student, activity)
    @student  = student
    @activity = activity
    @lang     = student.language.presence || "pt"
    @copy     = INACTIVITY.fetch(@lang, INACTIVITY["fr"])
    @url      = solve_activity_url(activity)

    mail(to: student.email, subject: @copy[:subject])
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
