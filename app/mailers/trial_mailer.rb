class TrialMailer < ApplicationMailer
  INTERNAL_EMAIL = "contato@practicebr.com".freeze

  # O papel deste email mudou em 2026-07-31. Antes ele era o portão: a pessoa
  # se cadastrava e só entrava clicando aqui. Hoje a landing já a coloca dentro
  # do app, então quando este email chega ela **já está praticando** — e o texto
  # precisa dizer isso, senão manda alguém "entrar" num lugar onde já está.
  #
  # Agora ele é o caminho de volta: guarda o link pra quando ela fechar o
  # navegador. Ver TrialStartToken e TrialStartsController.
  WELCOME = {
    "fr" => {
      subject: "Votre lien pour revenir sur Practice-BR",
      title:   "Gardez ce lien",
      lead:    "Vous êtes déjà sur Practice-BR — cet email est là pour que vous retrouviez le chemin quand vous reviendrez.",
      includes: "Votre essai comprend",
      level:   "Niveau enregistré",
      count:   "Jusqu'à <strong>3 activités</strong> à votre niveau",
      until:   "Valable jusqu'au",
      cta:     "Retourner sur Practice-BR →",
      note:    "En cliquant, vous créerez un mot de passe pour garder votre progression. Ce lien est valable 6 heures ; passé ce délai, utilisez « mot de passe oublié » sur la page de connexion.",
      after:   "Une fois les 3 activités terminées, vous pourrez vous abonner pour continuer.",
      footer:  "© Practice-BR · Ceci est un message automatique, merci de ne pas y répondre."
    },
    "en" => {
      subject: "Your link back to Practice-BR",
      title:   "Keep this link",
      lead:    "You're already on Practice-BR — this email is here so you can find your way back later.",
      includes: "Your trial includes",
      level:   "Registered level",
      count:   "Up to <strong>3 activities</strong> at your level",
      until:   "Valid until",
      cta:     "Back to Practice-BR →",
      note:    "Clicking will let you create a password to keep your progress. This link is valid for 6 hours; after that, use \"forgot password\" on the sign-in page.",
      after:   "Once you've done the 3 activities, you can subscribe to keep going.",
      footer:  "© Practice-BR · This is an automated message, please do not reply."
    },
    "pt" => {
      subject: "Seu link para voltar à Practice-BR",
      title:   "Guarde este link",
      lead:    "Você já está na Practice-BR — este email existe para você achar o caminho de volta depois.",
      includes: "Seu teste inclui",
      level:   "Nível cadastrado",
      count:   "Até <strong>3 atividades</strong> no seu nível",
      until:   "Válido até",
      cta:     "Voltar para a Practice-BR →",
      note:    "Ao clicar, você vai criar uma senha para guardar seu progresso. O link vale por 6 horas; depois disso, use \"esqueci minha senha\" na tela de entrada.",
      after:   "Quando terminar as 3 atividades, você pode assinar para continuar.",
      footer:  "© Practice-BR · Este é um email automático, por favor não responda."
    }
  }.freeze

  def welcome_email(user, reset_token)
    @user        = user
    @reset_token = reset_token
    @login_url   = edit_user_password_url(reset_password_token: reset_token, host: default_url_options[:host], protocol: default_url_options[:protocol] || "https")
    @expires_at  = format_date(user.trial_expires_at.to_date, user.language)
    @copy        = WELCOME.fetch(user.language, WELCOME["fr"])

    mail(to: user.email, subject: @copy[:subject])
  end

  def notification_email(user)
    @user       = user
    @expires_at = user.trial_expires_at

    mail(to: INTERNAL_EMAIL, subject: "Novo trial cadastrado: #{user.email} (#{user.level})")
  end

  def reminder_email(user)
    @user          = user
    @expires_at    = user.trial_expires_at
    @days_since    = ((Time.current - user.created_at) / 1.day).round
    @days_left     = [((@expires_at - Time.current) / 1.day).ceil, 0].max
    @login_url     = new_user_session_url(host: default_url_options[:host], protocol: default_url_options[:protocol] || "https")

    mail(to: user.email, subject: "Faltam #{@days_left} #{@days_left == 1 ? 'dia' : 'dias'} para o fim do seu teste na Practice-BR")
  end
end
