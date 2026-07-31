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

  # Conta apagada pelo próprio aluno.
  #
  # Deliberadamente SEM o email nem o nome dele: a conta acabou de ser apagada
  # a pedido, e guardar o dado pessoal numa caixa de entrada contradiz a
  # exclusão. O id do usuário e o id de cliente do Stripe bastam pra você
  # reconciliar com o painel, e não identificam a pessoa fora dos nossos
  # sistemas.
  def account_deleted_notification(user_id:, role:, stripe_customer_id:)
    @user_id            = user_id
    @role               = role
    @stripe_customer_id = stripe_customer_id
    mail(to: DAISY_EMAIL, subject: "🗑️ Conta apagada pelo próprio usuário — ##{user_id}")
  end

  # A exclusão foi abortada porque o cancelamento no Stripe falhou. Precisa de
  # ação manual: cancelar a assinatura no painel e avisar a pessoa.
  def account_deletion_failed_notification(user_id, error_message)
    @user_id       = user_id
    @error_message = error_message
    mail(to: DAISY_EMAIL, subject: "⚠️ Exclusão de conta abortada — ##{user_id}")
  end

  # Relatório da varredura de retenção. Chega só nos dias em que houve alguma
  # coisa — ver AccountRetentionJob#report. Serve de olho humano sobre o único
  # processo do app que apaga dado sozinho: se um dia aparecerem 40 exclusões,
  # você quer descobrir por email e não por um aluno reclamando.
  def retention_report(warned:, deleted:, failed:)
    @warned  = warned
    @deleted = deleted
    @failed  = failed
    subject  = "🌱 Retenção · #{deleted.size} apagada(s), #{warned.size} avisada(s)"
    subject += " · #{failed.size} FALHA(S)" if failed.any?
    mail(to: DAISY_EMAIL, subject: subject)
  end

  def draft_generation_failed(level, error_key)
    @level = level
    @error_key = error_key
    @generate_url = "https://app.practicebr.com/activities/generate_with_ai"
    mail(to: DAISY_EMAIL, subject: "⚠️ Falha ao gerar atividade #{level} — Practice-BR")
  end
end
