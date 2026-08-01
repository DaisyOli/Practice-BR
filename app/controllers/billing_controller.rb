class BillingController < ApplicationController
  # Na língua de quem lê: a maior parte de quem paga chegou pela landing em
  # francês. Mesmo padrão do TrialStartsController.
  PASSWORD_SAVED = {
    "fr" => "Mot de passe enregistré. Vous pouvez revenir quand vous voulez.",
    "en" => "Password saved. You can come back whenever you want.",
    "pt" => "Senha salva. Você pode voltar quando quiser."
  }.freeze

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

  # A senha nasce aqui, e não antes: quem vem da landing atravessa o trial
  # inteiro sem criar uma (a conta nasce com uma aleatória). Enquanto o acesso
  # era o cookie de "lembrar de mim" e o link de 8 dias do email, isso funcionou
  # — mas os dois vencem. Duas semanas depois de pagar, a pessoa encontrava uma
  # tela de login pedindo uma senha que ela nunca escolheu.
  #
  # Este é o único momento do fluxo em que pedir a senha faz sentido pra ela:
  # acabou de pagar, está com a compra fresca na cabeça e ainda não fechou a aba.
  def create_password
    # Quem já tem senha não passa por aqui. Trocar senha sem pedir a atual é
    # justamente o que o Devise evita com o `current_password` — a exceção só se
    # justifica pra quem não tem nenhuma pra informar.
    return redirect_to student_dashboard_path unless current_user.passwordless?

    if current_user.update(password_attrs)
      # Trocar a senha muda o salt que assina a sessão e o cookie de "lembrar de
      # mim": sem reemitir os dois, a pessoa seria deslogada na página seguinte,
      # bem depois de pagar. `force: true` porque o Warden ainda tem o usuário
      # antigo em cache neste request e um `sign_in` normal não faria nada.
      current_user.remember_me = true
      sign_in(current_user, force: true)

      redirect_to student_dashboard_path, notice: PASSWORD_SAVED.fetch(current_user.language, PASSWORD_SAVED["fr"])
    else
      # Sem flash: o erro sai na caixa dentro do formulário, ao lado dos campos.
      # Um toast no canto da tela obrigaria a pessoa a olhar pra dois lugares
      # pra entender que a confirmação não bateu.
      render :success, status: :unprocessable_entity
    end
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

  # O nome só entra quando vem preenchido: o campo é opcional, e um envio vazio
  # não pode apagar o nome de quem já tem um.
  def password_attrs
    attrs = {
      password:              params.dig(:user, :password),
      password_confirmation: params.dig(:user, :password_confirmation)
    }
    nome = params.dig(:user, :name).to_s.strip
    attrs[:name] = nome if nome.present?
    attrs
  end

  def no_open_invoice
    redirect_to billing_payment_problem_path, alert: NO_OPEN_INVOICE
  end
end
