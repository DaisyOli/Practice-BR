class BillingController < ApplicationController
  def new
  end

  def create_checkout
    price_id = params[:plan] == "annual" \
      ? ENV["STRIPE_PRICE_ANNUAL"] \
      : ENV["STRIPE_PRICE_MONTHLY"]

    session = Stripe::Checkout::Session.create(
      customer_email: current_user.email,
      mode:           "subscription",
      line_items:     [{ price: price_id, quantity: 1 }],
      success_url:    billing_success_url,
      cancel_url:     billing_cancel_url,
      metadata:       { user_id: current_user.id }
    )

    redirect_to session.url, allow_other_host: true
  rescue Stripe::StripeError => e
    Rails.logger.error "[Billing] Stripe error: #{e.message}"
    redirect_to billing_new_path, alert: "Erro ao iniciar pagamento. Tente novamente."
  end

  def success
  end

  def cancel
  end

  # Tela mostrada quando a tolerância de pagamento venceu (ver
  # ApplicationController#check_payment_status!).
  def payment_problem
  end

  # Manda o aluno pra fatura em aberto no Stripe, onde ele paga com outro cartão.
  #
  # Por que não abrir um checkout novo: o Checkout cria uma assinatura NOVA. O
  # aluno terminaria com duas, e a antiga continuaria falhando. A fatura aberta
  # quita a assinatura que já existe.
  NO_OPEN_INVOICE = "Não encontramos uma fatura em aberto. Fale com a gente que a gente resolve.".freeze

  def update_payment
    customer_id = current_user.stripe_customer_id
    return no_open_invoice if customer_id.blank?

    invoice = Stripe::Invoice.list(customer: customer_id, status: "open", limit: 1).data.first
    url     = invoice&.hosted_invoice_url

    # Sem fatura aberta: ou ela já foi paga, ou o Stripe ainda não gerou a próxima.
    return no_open_invoice if url.blank?

    redirect_to url, allow_other_host: true
  rescue Stripe::StripeError => e
    Rails.logger.error "[Billing] Stripe invoice error · user ##{current_user.id}: #{e.message}"
    no_open_invoice
  end

  def cancel_subscription
    sub_id = current_user.stripe_subscription_id
    unless sub_id.present?
      redirect_to student_dashboard_path, alert: "Nenhuma assinatura ativa encontrada."
      return
    end

    Stripe::Subscription.update(sub_id, { cancel_at_period_end: true })
    current_user.update!(subscription_status: "canceling")
    redirect_to student_dashboard_path, notice: "cancel_confirmed"
  rescue Stripe::StripeError => e
    Rails.logger.error "[Billing] Stripe cancel error: #{e.message}"
    redirect_to student_dashboard_path, alert: "Erro ao cancelar. Tente novamente."
  end

  private

  def no_open_invoice
    redirect_to billing_payment_problem_path, alert: NO_OPEN_INVOICE
  end
end
