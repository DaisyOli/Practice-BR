class WebhooksController < ApplicationController
  skip_before_action :authenticate_user!
  skip_before_action :verify_authenticity_token
  skip_before_action :check_trial_restrictions!

  def stripe
    payload = request.body.read
    sig_header = request.env["HTTP_STRIPE_SIGNATURE"]

    begin
      event = Stripe::Webhook.construct_event(
        payload, sig_header, ENV["STRIPE_WEBHOOK_SECRET"]
      )
    rescue JSON::ParserError, Stripe::SignatureVerificationError => e
      Rails.logger.error "[Webhook] Invalid: #{e.message}"
      return head :bad_request
    end

    case event["type"]
    when "checkout.session.completed"
      handle_checkout_completed(event["data"]["object"])
    when "invoice.payment_succeeded"
      handle_payment_succeeded(event["data"]["object"])
    when "invoice.payment_failed"
      handle_payment_failed(event["data"]["object"])
    when "customer.subscription.updated"
      handle_subscription_updated(event["data"]["object"])
    when "customer.subscription.deleted"
      handle_subscription_deleted(event["data"]["object"])
    end

    head :ok
  end

  private

  # Fim do período de cobrança, aceitando os DOIS formatos do Stripe.
  #
  # Na versão de API 2025-03-31.basil o Stripe tirou `current_period_end` do
  # objeto Subscription e moveu para os ITENS da assinatura. Os dois formatos
  # convivem neste app: a gem 13.x fixa `Stripe-Version: 2025-02-24.acacia`, então
  # `Stripe::Subscription.retrieve` ainda devolve o formato antigo, enquanto o
  # payload do webhook chega na versão configurada no painel do Stripe — que já é
  # a nova. Foi essa assimetria que derrubou o handler em 03/08/2026: das três
  # leituras idênticas, só a do webhook quebrou.
  #
  # Nada de `dig` aqui: o objeto é um `Stripe::StripeObject`, não um Hash, e não
  # responde a `dig` (NoMethodError). Só `[]` encadeado funciona nos dois.
  def period_end_from(subscription)
    raw = subscription["current_period_end"]

    if raw.blank?
      itens    = subscription["items"]
      primeiro = itens && itens["data"] && itens["data"].first
      raw      = primeiro && primeiro["current_period_end"]
    end

    if raw.blank?
      Rails.logger.warn "[Webhook] ⚠️ Assinatura sem current_period_end em nenhum dos dois formatos"
      return nil
    end

    Time.at(raw).utc
  end

  def handle_checkout_completed(session)
    user = User.find_by(id: session["metadata"]&.[]("user_id"))
    return unless user

    subscription = Stripe::Subscription.retrieve(session["subscription"])

    attrs = {
      role:                   "student",
      stripe_customer_id:     session["customer"],
      stripe_subscription_id: session["subscription"],
      subscription_status:    "active"
    }
    # Quem pagou entra mesmo sem a data. O acesso vem primeiro; a data se corrige
    # sozinha no próximo invoice.payment_succeeded. Bloquear a ativação por causa
    # de um campo ausente seria cobrar e não entregar.
    if (period_end = period_end_from(subscription))
      attrs[:subscription_current_period_end] = period_end
    end

    user.update!(attrs)
    Rails.logger.info "[Webhook] ✅ Assinatura ativada · user ##{user.id}"

    # Até aqui quem pagava saía do Stripe com um recibo e mais nada nosso. O
    # email diz o que a assinatura abriu e, pra quem ainda não tem senha, carrega
    # o link que cria uma.
    StudentMailer.subscription_welcome(user, password_token_for(user)).deliver_later
  end

  # Token de senha só pra quem não tem senha nenhuma. Quem já criou a sua não
  # precisa de um link de redefinição chegando sozinho na caixa de entrada.
  #
  # `update_columns` de propósito: grava os dois campos sem passar pelas
  # validações nem pelo callback que carimba `password_set_at` — gerar o token
  # não é escolher uma senha.
  def password_token_for(user)
    return nil unless user.passwordless?

    raw_token, hashed_token = Devise.token_generator.generate(User, :reset_password_token)
    user.update_columns(reset_password_token: hashed_token, reset_password_sent_at: Time.current)
    raw_token
  end

  def handle_payment_succeeded(invoice)
    user = User.find_by(stripe_customer_id: invoice["customer"])
    return unless user

    if invoice["subscription"].present?
      subscription = Stripe::Subscription.retrieve(invoice["subscription"])
      if (period_end = period_end_from(subscription))
        user.update!(subscription_current_period_end: period_end)
      end
      # Pagou: encerra qualquer tolerância em curso e zera o contador, senão uma
      # falha futura herdaria a data antiga e expiraria na hora.
      user.clear_payment_past_due!(status: subscription["cancel_at_period_end"] ? "canceling" : "active")
    end
  end

  def handle_payment_failed(invoice)
    user = User.find_by(stripe_customer_id: invoice["customer"])
    return unless user

    first_failure = user.past_due_since.nil?
    user.mark_payment_past_due!
    Rails.logger.warn "[Webhook] ⚠️ Falha de pagamento · user ##{user.id}"

    # Só avisa na primeira falha. O Stripe reenvia este evento a cada nova
    # tentativa do cartão, e um email por tentativa viraria spam.
    return unless first_failure

    StudentMailer.payment_failed(user).deliver_later
    AdminMailer.payment_failed_notification(user).deliver_later
  end

  def handle_subscription_updated(subscription)
    user = User.find_by(stripe_subscription_id: subscription["id"])
    return unless user

    # A data é a parte menos importante deste handler — quem decide acesso é o
    # bloco de status logo abaixo. Levantar aqui por causa dela devolvia 500 ao
    # Stripe e, pior, impedia o status de ser aplicado: quem cancelava continuava
    # `active` e quem estava com o cartão recusado nunca virava `past_due`.
    if (period_end = period_end_from(subscription))
      user.update!(subscription_current_period_end: period_end)
    end

    # O status vem do Stripe em vez de ser inferido: antes este handler assumia
    # "active" sempre que não houvesse cancelamento agendado, então um
    # subscription.updated qualquer apagava um past_due em curso e devolvia
    # acesso a quem estava com o cartão recusado.
    if subscription["cancel_at_period_end"]
      user.clear_payment_past_due!(status: "canceling")
    elsif %w[past_due unpaid].include?(subscription["status"])
      user.mark_payment_past_due!
    else
      user.clear_payment_past_due!(status: "active")
    end

    Rails.logger.info "[Webhook] 🔄 Assinatura atualizada · user ##{user.id} → #{user.subscription_status}"
  end

  def handle_subscription_deleted(subscription)
    user = User.find_by(stripe_subscription_id: subscription["id"])
    return unless user

    user.role = "trial"
    user.subscription_status = "canceled"

    # `validate: false` de propósito, por causa de uma armadilha na transição de
    # papel: a validação de presença de `level` só vale `if: :trial?`, então um
    # `student` com nível vazio é um estado válido — e alcançável (o professor
    # pode limpar o nível em teachers#update_student_level, e o convite feito por
    # admin não pergunta o nível). No instante em que o papel vira `trial`, aquele
    # nível vazio passa a violar a validação.
    #
    # Com `update!`, o rebaixamento explodiria: o Stripe receberia 500, tentaria
    # de novo, falharia igual — e o aluno ficaria com acesso de pagante pra
    # sempre, de graça. São dois campos de estado vindos de um sistema externo;
    # não há entrada de usuário pra validar aqui.
    user.save!(validate: false)

    Rails.logger.info "[Webhook] ❌ Assinatura cancelada · user ##{user.id}"
  end
end
