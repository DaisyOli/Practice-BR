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
      note:    "En cliquant, vous créerez un mot de passe pour garder votre progression. Ce lien reste valable pendant toute la durée de votre essai.",
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
      note:    "Clicking will let you create a password to keep your progress. This link stays valid for the whole length of your trial.",
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
      note:    "Ao clicar, você vai criar uma senha para guardar seu progresso. O link continua valendo durante todo o seu teste.",
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

  # Lembrete do 3º dia, pra quem COMEÇOU e não terminou as 3 atividades. Quem
  # não começou recebe o de ativação — falar "continue praticando" com quem
  # nunca praticou é falar com a pessoa errada.
  #
  # Estava inteiro em português fixo até 2026-08-01, inclusive pra francês, e
  # ainda mandava "fale com um professor" — caminho que não existe mais desde
  # que o fim do teste passou a ter um só destino, a assinatura.
  REMINDER = {
    "fr" => {
      subject: "Il vous reste des activités · ainda tem atividades ⏳",
      title:   "Vous avez commencé, il reste des activités",
      lead:    "Vous avez fait %{feitas} des 3 activités de votre essai. Les autres sont toujours là, à votre niveau.",
      left:    "Il vous reste %{dias} jour(s) d'essai",
      cta:     "Continuer →",
      footer:  "© Practice-BR · Ceci est un message automatique, merci de ne pas y répondre."
    },
    "en" => {
      subject: "You still have activities left · ainda tem atividades ⏳",
      title:   "You started — there are activities left",
      lead:    "You've done %{feitas} of the 3 activities in your trial. The rest are still there, at your level.",
      left:    "%{dias} day(s) of trial left",
      cta:     "Keep going →",
      footer:  "© Practice-BR · This is an automated message, please do not reply."
    },
    "pt" => {
      subject: "Você ainda tem atividades no seu teste ⏳",
      title:   "Você começou — e ainda tem atividades",
      lead:    "Você fez %{feitas} das 3 atividades do seu teste. As outras continuam lá, no seu nível.",
      left:    "Faltam %{dias} dia(s) de teste",
      cta:     "Continuar →",
      footer:  "© Practice-BR · Este é um email automático, por favor não responda."
    }
  }.freeze

  def reminder_email(user)
    @user       = user
    @copy       = REMINDER.fetch(user.language, REMINDER["fr"])
    @days_left  = [((user.trial_expires_at - Time.current) / 1.day).ceil, 0].max
    @feitas     = user.trial_activities_used.to_i
    @expires_at = format_date(user.trial_expires_at.to_date, user.language)
    @url        = student_dashboard_url

    mail(to: user.email, subject: @copy[:subject])
  end

  # ---- A sequência que faltava ------------------------------------------------
  #
  # Medido em 2026-08-01: de 5 pessoas reais que entraram no teste, 4 nunca
  # responderam UMA questão. O gargalo não é o paywall — quase ninguém chega
  # nele. E quem chegava ao fim do teste sem assinar nunca mais era procurado: o
  # próximo email possível era o aviso de exclusão de conta, 11 meses depois.
  #
  # São três momentos, um email cada, no máximo três na vida da pessoa.

  # 1. Entrou e não começou (D+1). O email mais importante dos três.
  ACTIVATION = {
    "fr" => {
      subject: "Votre première activité · sua primeira atividade 🌱",
      title:   "On commence par celle-ci ?",
      lead:    "Vous avez créé votre accès hier et vos 3 activités sont toujours là. Celle-ci prend quelques minutes — commencer est la partie difficile, le reste vient tout seul.",
      cta:     "Faire cette activité →",
      note:    "Votre essai est ouvert encore %{dias} jour(s)."
    },
    "en" => {
      subject: "Your first activity · sua primeira atividade 🌱",
      title:   "Shall we start with this one?",
      lead:    "You created your access yesterday and your 3 activities are still waiting. This one takes a few minutes — starting is the hard part, the rest follows.",
      cta:     "Do this activity →",
      note:    "Your trial stays open for %{dias} more day(s)."
    },
    "pt" => {
      subject: "Sua primeira atividade está esperando 🌱",
      title:   "Vamos começar por esta?",
      lead:    "Você criou seu acesso ontem e suas 3 atividades continuam lá. Esta leva poucos minutos — começar é a parte difícil, o resto vem sozinho.",
      cta:     "Fazer esta atividade →",
      note:    "Seu teste fica aberto por mais %{dias} dia(s)."
    }
  }.freeze

  def activation_email(user, activity)
    @user     = user
    @activity = activity
    @copy     = ACTIVATION.fetch(user.language, ACTIVATION["fr"])
    @dias     = [((user.trial_expires_at - Time.current) / 1.day).ceil, 0].max
    @url      = solve_activity_url(activity)

    mail(to: user.email, subject: @copy[:subject])
  end

  # 2. O teste acabou (esgotou as 3 ou venceu o prazo). Até aqui isso só existia
  #    como tela dentro do app: só via quem voltasse sozinha.
  # Dois textos, e a diferença não é cosmética: "você viu o que o teste tinha" é
  # mentira para quem não abriu uma atividade sequer — e essas eram 4 das 5
  # pessoas. Para elas o email não pode soar a balanço nem a cobrança; o teste
  # passou, a vida acontece, e a porta continua aberta.
  ENDED = {
    "fr" => {
      subject:      "Votre essai est terminé · e agora?",
      title:        "Vous avez fait le tour de l'essai",
      title_unused: "Votre essai s'est terminé",
      lead:         "L'essai s'arrête ici. Ce que vous avez vu était une porte d'entrée : il y a %{total} activités jusqu'à votre niveau, et les niveaux précédents restent ouverts pour réviser.",
      lead_unused:  "Les sept jours sont passés sans qu'on se croise — ça arrive, et ce n'est pas grave. Les %{total} activités de votre niveau sont toujours là, et votre place aussi.",
      cta:          "Voir les formules →",
      note:         "Votre compte reste tel quel — rien ne se perd si vous revenez plus tard."
    },
    "en" => {
      subject:      "Your trial has ended · e agora?",
      title:        "You've seen what the trial holds",
      title_unused: "Your trial has ended",
      lead:         "The trial stops here. What you saw was the front door: there are %{total} activities up to your level, and previous levels stay open for review.",
      lead_unused:  "The seven days went by without us crossing paths — it happens, and it's no big deal. The %{total} activities at your level are still there, and so is your spot.",
      cta:          "See the plans →",
      note:         "Your account stays as it is — nothing is lost if you come back later."
    },
    "pt" => {
      subject:      "Seu teste terminou — e agora?",
      title:        "Você viu o que o teste tinha",
      title_unused: "Seu teste terminou",
      lead:         "O teste para por aqui. O que você viu era a porta de entrada: são %{total} atividades até o seu nível, e os níveis anteriores continuam abertos para revisar.",
      lead_unused:  "Os sete dias passaram sem a gente se encontrar — acontece, e não tem problema nenhum. As %{total} atividades do seu nível continuam aqui, e o seu lugar também.",
      cta:          "Ver os planos →",
      note:         "Sua conta fica como está — nada se perde se você voltar depois."
    }
  }.freeze

  def ended_email(user, total_activities)
    @user   = user
    copy    = ENDED.fetch(user.language, ENDED["fr"])
    usou    = user.trial_activities_used.to_i.positive?
    @title  = usou ? copy[:title] : copy[:title_unused]
    @lead   = (usou ? copy[:lead] : copy[:lead_unused]) % { total: total_activities }
    @copy   = copy
    @url    = billing_new_url

    mail(to: user.email, subject: copy[:subject])
  end

  # 3. A volta, dias depois. O último email antes do silêncio — e ele diz isso,
  #    porque prometer silêncio e cumprir é o que faz alguém abrir o próximo.
  WINBACK = {
    "fr" => {
      subject: "On vous a gardé une place · uma última coisa",
      title:   "Si ce n'était pas le bon moment",
      lead:    "Votre essai s'est terminé il y a quelques jours. Il n'y a rien à rattraper : les activités sont toujours là, à votre niveau, et celle-ci vous attend.",
      cta:     "Reprendre →",
      note:    "C'est le dernier email que nous vous envoyons à ce sujet."
    },
    "en" => {
      subject: "We kept your spot · uma última coisa",
      title:   "If it wasn't the right time",
      lead:    "Your trial ended a few days ago. There's nothing to catch up on: the activities are still there, at your level, and this one is waiting.",
      cta:     "Pick it back up →",
      note:    "This is the last email we'll send you about this."
    },
    "pt" => {
      subject: "Guardamos seu lugar — uma última coisa",
      title:   "Se não era a hora",
      lead:    "Seu teste terminou há alguns dias. Não tem nada para recuperar: as atividades continuam lá, no seu nível, e esta aqui está esperando.",
      cta:     "Voltar →",
      note:    "Este é o último email que mandamos sobre isso."
    }
  }.freeze

  def winback_email(user, activity)
    @user     = user
    @activity = activity
    @copy     = WINBACK.fetch(user.language, WINBACK["fr"])
    @url      = billing_new_url

    mail(to: user.email, subject: @copy[:subject])
  end
end
