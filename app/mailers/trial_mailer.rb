class TrialMailer < ApplicationMailer
  include MarketingEmail

  # Boas-vindas fica de fora: é o email que a pessoa pediu ao se cadastrar, e o
  # que guarda o caminho de volta. O notification_email vai para a Daisy.
  marketing :first_nudge_email, :activation_email, :reminder_email, :reopen_email,
            :ended_email, :winback_email, :recovery_email

  INTERNAL_EMAIL = "contato@practicebr.com".freeze

  # O papel deste email mudou duas vezes.
  #
  # Até 2026-07-31 ele era o portão: a pessoa só entrava clicando aqui. Depois
  # virou "o caminho de volta" e passou a dizer "você já está na Practice-BR" —
  # o que só é verdade se o redirecionamento da landing deu certo. E o botão
  # levava para "Criar nova senha": voltar exigia inventar uma senha, a mesma
  # barreira que zerou a ativação em julho.
  #
  # Desde 2026-10-14 ele serve aos dois casos com uma frase só: boas-vindas e um
  # botão que leva direto à primeira atividade, já logado, de qualquer aparelho
  # (TrialEmailLink). Quem já está dentro cai na atividade; quem fechou a aba
  # também. A senha continua sendo pedida no fim do teste, não no começo.
  WELCOME = {
    "fr" => {
      subject:  "Bienvenue sur Practice-BR · votre première activité 🌱",
      title:    "Bienvenue sur Practice-BR",
      lead:     "Votre essai gratuit est ouvert. Ce sont des activités courtes de portugais, à votre niveau, avec le résultat tout de suite — la première prend quelques minutes.",
      includes: "Votre essai comprend",
      level:    "Niveau",
      count:    "<strong>3 activités</strong> à votre niveau",
      until:    "Ouvert jusqu'au",
      cta:      "Commencer mon premier exercice →",
      note:     "Ce bouton vous fait entrer directement, sans mot de passe, depuis n'importe quel appareil. Gardez cet email : il vous ramène ici pendant tout l'essai.",
      after:    "Une fois les 3 activités terminées, vous pourrez vous abonner pour continuer.",
      footer:   "© Practice-BR · Ceci est un message automatique, merci de ne pas y répondre."
    },
    "en" => {
      subject:  "Welcome to Practice-BR · your first activity 🌱",
      title:    "Welcome to Practice-BR",
      lead:     "Your free trial is open. These are short Portuguese activities at your level, with your result right away — the first one takes a few minutes.",
      includes: "Your trial includes",
      level:    "Level",
      count:    "<strong>3 activities</strong> at your level",
      until:    "Open until",
      cta:      "Start my first exercise →",
      note:     "This button takes you straight in, no password needed, from any device. Keep this email: it brings you back here for the whole trial.",
      after:    "Once you've done the 3 activities, you can subscribe to keep going.",
      footer:   "© Practice-BR · This is an automated message, please do not reply."
    },
    "pt" => {
      subject:  "Boas-vindas à Practice-BR · sua primeira atividade 🌱",
      title:    "Boas-vindas à Practice-BR",
      lead:     "Seu teste gratuito está aberto. São atividades curtas de português, no seu nível, com o resultado na hora — a primeira leva poucos minutos.",
      includes: "Seu teste inclui",
      level:    "Nível",
      count:    "<strong>3 atividades</strong> no seu nível",
      until:    "Aberto até",
      cta:      "Começar meu primeiro exercício →",
      note:     "Este botão te leva direto pra dentro, sem senha, de qualquer aparelho. Guarde este email: ele te traz de volta durante todo o teste.",
      after:    "Quando terminar as 3 atividades, você pode assinar para continuar.",
      footer:   "© Practice-BR · Este é um email automático, por favor não responda."
    }
  }.freeze

  # O segundo argumento era o token de redefinir senha, que o botão usava. Ficou
  # opcional e ignorado só para os emails que já estavam na fila no momento do
  # deploy não quebrarem por número de argumentos.
  def welcome_email(user, _legacy_reset_token = nil)
    @user       = user
    @activity   = user.suggested_first_activity
    @login_url  = trial_entry_url(user, to: @activity ? "activity" : "dashboard", activity: @activity)
    @expires_at = format_date(user.trial_expires_at.to_date, user.language)
    @copy       = WELCOME.fetch(user.language, WELCOME["fr"])

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
    @url        = trial_entry_url(user, to: "dashboard")

    mail(to: user.email, subject: @copy[:subject])
  end

  # Lembrete do mesmo dia (≥ 4h depois do cadastro), pra quem ainda não fez
  # nenhuma atividade. Existe por causa de um padrão medido em 2026-08-03: de
  # quem começou, todo mundo começou no mesmo dia — 0h, 0,2h, 0,3h, 0,8h, 15h.
  # Ninguém começou no dia seguinte. O D+1 chegava tarde para a janela em que a
  # vontade ainda está quente.
  FIRST_NUDGE = {
    "fr" => {
      subject: "Cinq minutes de portugais aujourd'hui ? · cinco minutinhos 🌱",
      title:   "Votre première activité est prête",
      lead:    "Vous avez ouvert votre essai tout à l'heure. On vous a choisi une activité à votre niveau : quelques minutes suffisent, et vous voyez votre résultat tout de suite.",
      cta:     "Commencer mon premier exercice →",
      note:    "Votre essai est ouvert jusqu'au %{ate}. Le bouton vous fait entrer directement, sans mot de passe."
    },
    "en" => {
      subject: "Five minutes of Portuguese today? · cinco minutinhos 🌱",
      title:   "Your first activity is ready",
      lead:    "You opened your trial earlier today. We picked an activity at your level: a few minutes is enough, and you see your result right away.",
      cta:     "Start my first exercise →",
      note:    "Your trial is open until %{ate}. The button takes you straight in, no password needed."
    },
    "pt" => {
      subject: "Cinco minutinhos de português hoje? 🌱",
      title:   "Sua primeira atividade está pronta",
      lead:    "Você abriu seu teste há pouco. Escolhemos uma atividade no seu nível: poucos minutos bastam, e você vê o resultado na hora.",
      cta:     "Começar meu primeiro exercício →",
      note:    "Seu teste está aberto até %{ate}. O botão te leva direto pra dentro, sem senha."
    }
  }.freeze

  def first_nudge_email(user, activity)
    @user     = user
    @activity = activity
    @copy     = FIRST_NUDGE.fetch(user.language, FIRST_NUDGE["fr"])
    @note     = @copy[:note] % { ate: format_date(user.trial_expires_at.to_date, user.language) }
    @url      = trial_entry_url(user, to: "activity", activity: activity)

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
    @url      = trial_entry_url(user, to: "activity", activity: activity)

    mail(to: user.email, subject: @copy[:subject])
  end

  # 2. Nunca chegou a usar o teste. Este email devolve o que a pessoa não usou,
  #    em vez de pedir dinheiro por algo que ela nunca viu.
  #
  #    Ele carrega um link de acesso novo, e isso não é detalhe: quem entrou pela
  #    landing nunca criou senha, e o link do email original vale 8 dias. Passado
  #    o prazo, essa pessoa está **trancada para fora da própria conta** — um
  #    convite sem link novo seria um convite para uma porta fechada.
  #
  #    Até 2026-10-14 o link novo era o de redefinir senha: reabrir o teste
  #    passava por "Criar nova senha". Agora é o TrialEmailLink, que entra direto.
  REOPEN = {
    "fr" => {
      subject: "On vous rouvre l'essai · seu teste, de novo 🌱",
      title:   "Vos 3 activités n'ont jamais servi",
      lead:    "Vous aviez créé un accès et la semaine est passée sans qu'on se croise. Ça arrive. On vous rouvre l'essai pour 7 jours — mêmes 3 activités, à votre niveau, sans rien payer.",
      cta:     "Ouvrir mon essai →",
      note:    "Ce lien vous fait entrer directement, sans mot de passe. Il est valable 8 jours."
    },
    "en" => {
      subject: "We're reopening your trial · seu teste, de novo 🌱",
      title:   "Your 3 activities were never used",
      lead:    "You created an access and the week went by without us crossing paths. It happens. We're reopening your trial for 7 days — same 3 activities, at your level, nothing to pay.",
      cta:     "Open my trial →",
      note:    "This link takes you straight in, no password needed. It's valid for 8 days."
    },
    "pt" => {
      subject: "Reabrimos seu teste 🌱",
      title:   "Suas 3 atividades nunca foram usadas",
      lead:    "Você criou um acesso e a semana passou sem a gente se encontrar. Acontece. Reabrimos seu teste por 7 dias — as mesmas 3 atividades, no seu nível, sem pagar nada.",
      cta:     "Abrir meu teste →",
      note:    "Este link te leva direto pra dentro, sem senha. Vale por 8 dias."
    }
  }.freeze

  def reopen_email(user, activity = nil)
    @user     = user
    @copy     = REOPEN.fetch(user.language, REOPEN["fr"])
    @activity = nil
    @url      = trial_entry_url(user, to: activity ? "activity" : "dashboard", activity: activity)

    mail(to: user.email, subject: @copy[:subject])
  end

  # 3. O teste acabou (esgotou as 3 ou venceu o prazo). Até aqui isso só existia
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
    @url    = trial_entry_url(user, to: "billing")

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
    @url      = trial_entry_url(user, to: "billing")

    mail(to: user.email, subject: @copy[:subject])
  end

  # ---- Recuperação manual (TrialRecovery) ------------------------------------
  #
  # Não faz parte da sequência automática: sai uma vez, por decisão da Daisy,
  # para quem se cadastrou antes de 2026-10-14 — quando os emails ainda
  # levavam a uma tela de login ou a "Criar nova senha" para quem não tinha
  # senha. O texto admite isso, porque é justamente o que ele corrige.
  #
  # Ele é montado em pedaços porque a mesma campanha fala com gente em
  # situações diferentes:
  #   - cadastro recente ou antigo ("há alguns dias" seria falso para julho);
  #   - quem recebeu o winback, que prometia ser o último email — quebrar a
  #     promessa em silêncio é pior que dizer por quê;
  #   - quem nunca começou ou quem fez 1–2 atividades.
  RECOVERY_RECENT = 14.days

  RECOVERY = {
    "fr" => {
      subject:      "Votre essai Practice-BR vous attend · seu teste 🌱",
      title:        "Revenir est plus simple maintenant",
      opening:      "Vous avez ouvert un essai sur Practice-BR il y a quelques jours.",
      opening_old:  "Vous avez ouvert un essai sur Practice-BR il y a quelque temps.",
      promise:      "On vous avait dit que notre dernier email serait le dernier ; on revient quand même, parce qu'on vous doit une correction.",
      fix:          "Si on vous a demandé un mot de passe pour revenir, c'était à nous de faire mieux : ce bouton vous fait entrer directement, sur n'importe quel appareil",
      fix_new:      ", et vous emmène à une activité choisie pour votre niveau.",
      fix_started:  ". Vous avez fait %{feitas} des 3 activités — la suivante vous attend.",
      cta:          "Commencer mon premier exercice →",
      cta_started:  "Continuer →",
      note:         "Votre essai est ouvert jusqu'au %{ate}.",
      extended:     "On vous a rouvert l'essai : il est ouvert jusqu'au %{ate}."
    },
    "en" => {
      subject:      "Your Practice-BR trial is waiting · seu teste 🌱",
      title:        "Coming back is simpler now",
      opening:      "You opened a trial on Practice-BR a few days ago.",
      opening_old:  "You opened a trial on Practice-BR a while ago.",
      promise:      "We told you our last email would be the last one; we're writing anyway, because we owe you a fix.",
      fix:          "If you were asked for a password to come back, that was on us: this button takes you straight in, on any device",
      fix_new:      ", to an activity picked for your level.",
      fix_started:  ". You've done %{feitas} of the 3 activities — the next one is waiting.",
      cta:          "Start my first exercise →",
      cta_started:  "Keep going →",
      note:         "Your trial is open until %{ate}.",
      extended:     "We've reopened your trial: it's open until %{ate}."
    },
    "pt" => {
      subject:      "Seu teste na Practice-BR está esperando 🌱",
      title:        "Voltar ficou mais simples",
      opening:      "Você abriu um teste na Practice-BR há alguns dias.",
      opening_old:  "Você abriu um teste na Practice-BR há algum tempo.",
      promise:      "A gente disse que o último email seria o último; voltamos mesmo assim, porque te devemos uma correção.",
      fix:          "Se pediram uma senha para você voltar, a falha foi nossa: este botão te leva direto pra dentro, de qualquer aparelho",
      fix_new:      ", numa atividade escolhida para o seu nível.",
      fix_started:  ". Você fez %{feitas} das 3 atividades — a próxima está esperando.",
      cta:          "Começar meu primeiro exercício →",
      cta_started:  "Continuar →",
      note:         "Seu teste está aberto até %{ate}.",
      extended:     "Reabrimos seu teste: ele está aberto até %{ate}."
    }
  }.freeze

  # `extended` vem de quem chama, não é deduzido aqui: só o TrialRecovery sabe
  # se a extensão foi concedida nesta rodada.
  def recovery_email(user, activity, extended: false)
    @user     = user
    @activity = activity
    copy      = RECOVERY.fetch(user.language, RECOVERY["fr"])
    feitas    = user.quiz_attempts.count
    recent    = (user.created_at || Time.current) > RECOVERY_RECENT.ago

    @copy = copy
    @lead = [
      recent ? copy[:opening] : copy[:opening_old],
      (copy[:promise] if user.trial_winback_sent_at.present?),
      copy[:fix] + (feitas.positive? ? copy[:fix_started] % { feitas: feitas } : copy[:fix_new])
    ].compact.join(" ")
    @cta  = feitas.positive? ? copy[:cta_started] : copy[:cta]
    @note = copy[extended ? :extended : :note] %
            { ate: format_date(user.trial_expires_at.to_date, user.language) }
    @url  = trial_entry_url(user, to: "activity", activity: activity)

    mail(to: user.email, subject: copy[:subject])
  end

  private

  # O link de todo botão dos emails do teste. Quem nunca escolheu senha recebe o
  # TrialEmailLink, que entra sem login; quem já tem senha recebe o endereço
  # normal, porque consegue entrar sozinha e o link de login não vale pra ela.
  def trial_entry_url(user, to:, activity: nil)
    if TrialEmailLink.usable_by?(user)
      trial_link_url(token: TrialEmailLink.generate(user, to: to, activity: activity))
    else
      case to
      when "activity" then activity ? solve_activity_url(activity) : student_dashboard_url
      when "billing"  then billing_new_url
      else                 student_dashboard_url
      end
    end
  end
end
