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

  def handle_checkout_completed(session)
    user = User.find_by(id: session["metadata"]&.[]("user_id"))
    return unless user

    subscription = Stripe::Subscription.retrieve(session["subscription"])

    user.update!(
      role:                         "student",
      stripe_customer_id:           session["customer"],
      stripe_subscription_id:       session["subscription"],
      subscription_status:          "active",
      subscription_current_period_end: Time.at(subscription["current_period_end"]).utc
    )
    Rails.logger.info "[Webhook] ✅ Assinatura ativada · user ##{user.id}"
  end

  def handle_payment_succeeded(invoice)
    user = User.find_by(stripe_customer_id: invoice["customer"])
    return unless user

    if invoice["subscription"].present?
      subscription = Stripe::Subscription.retrieve(invoice["subscription"])
      user.update!(subscription_current_period_end: Time.at(subscription["current_period_end"]).utc)
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

    user.update!(subscription_current_period_end: Time.at(subscription["current_period_end"]).utc)

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
