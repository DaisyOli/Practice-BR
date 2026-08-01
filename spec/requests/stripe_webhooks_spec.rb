require 'rails_helper'

# Specs dos handlers de webhook — a parte que roda contra dados reais de alunas
# pagantes e que não dá para testar à mão sem montar o modo de teste do Stripe
# com um cartão que falha de propósito.
#
# As requisições são assinadas de verdade (Stripe::Webhook::Signature), então
# estas specs também travam a verificação de assinatura: um payload sem
# assinatura válida tem que ser recusado.
RSpec.describe "Webhooks do Stripe", type: :request do
  WEBHOOK_SECRET = "whsec_teste_1234567890".freeze

  let!(:student) do
    create(:user, :student,
           email: "aluna@exemplo.fr",
           stripe_customer_id: "cus_123",
           stripe_subscription_id: "sub_123",
           subscription_status: "active",
           subscription_current_period_end: 1.month.from_now)
  end

  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("STRIPE_WEBHOOK_SECRET").and_return(WEBHOOK_SECRET)
  end

  # Monta o cabeçalho Stripe-Signature igual ao que o Stripe manda.
  def post_event(type, object, secret: WEBHOOK_SECRET)
    payload = { id: "evt_test", type: type, data: { object: object } }.to_json
    timestamp = Time.now
    signature = Stripe::Webhook::Signature.compute_signature(timestamp, payload, secret)
    header = Stripe::Webhook::Signature.generate_header(timestamp, signature)

    post "/webhooks/stripe", params: payload,
         headers: { "HTTP_STRIPE_SIGNATURE" => header, "CONTENT_TYPE" => "application/json" }
  end

  def stub_subscription(period_end: 1.month.from_now, cancel_at_period_end: false)
    allow(Stripe::Subscription).to receive(:retrieve).and_return(
      { "current_period_end" => period_end.to_i,
        "cancel_at_period_end" => cancel_at_period_end }
    )
  end

  describe "verificação de assinatura" do
    it "recusa payload com assinatura inválida" do
      post_event("invoice.payment_failed", { "customer" => "cus_123" }, secret: "whsec_outro_segredo")

      expect(response).to have_http_status(:bad_request)
      expect(student.reload.subscription_status).to eq("active")
    end

    it "recusa payload sem cabeçalho de assinatura" do
      post "/webhooks/stripe", params: { type: "invoice.payment_failed" }.to_json,
           headers: { "CONTENT_TYPE" => "application/json" }

      expect(response).to have_http_status(:bad_request)
    end
  end

  describe "invoice.payment_failed" do
    it "marca past_due, registra a data e avisa aluna e admin" do
      expect {
        post_event("invoice.payment_failed", { "customer" => "cus_123" })
      }.to change { ActionMailer::Base.deliveries.size + enqueued_mailer_count }.by(2)

      expect(response).to have_http_status(:ok)
      student.reload
      expect(student.subscription_status).to eq("past_due")
      expect(student.past_due_since).to be_within(5.seconds).of(Time.current)
    end

    it "não reinicia a contagem nem reenvia email nas tentativas seguintes" do
      primeira_falha = 4.days.ago
      student.update!(subscription_status: "past_due", past_due_since: primeira_falha)

      expect {
        post_event("invoice.payment_failed", { "customer" => "cus_123" })
      }.not_to change { enqueued_mailer_count }

      # A data da primeira falha tem que sobreviver: o Stripe reenvia este evento
      # a cada nova tentativa do cartão (até 8 vezes em 2 semanas).
      expect(student.reload.past_due_since).to be_within(1.second).of(primeira_falha)
    end

    it "ignora cliente que não existe no nosso banco" do
      expect {
        post_event("invoice.payment_failed", { "customer" => "cus_desconhecido" })
      }.not_to change { enqueued_mailer_count }

      expect(response).to have_http_status(:ok)
    end
  end

  describe "invoice.payment_succeeded" do
    it "encerra a tolerância e volta pra ativo" do
      student.update!(subscription_status: "past_due", past_due_since: 5.days.ago)
      stub_subscription(period_end: 1.year.from_now)

      post_event("invoice.payment_succeeded", { "customer" => "cus_123", "subscription" => "sub_123" })

      student.reload
      expect(student.subscription_status).to eq("active")
      expect(student.past_due_since).to be_nil
      expect(student.subscription_current_period_end).to be_within(1.day).of(1.year.from_now)
    end

    it "preserva o cancelamento agendado ao invés de reativar" do
      student.update!(subscription_status: "past_due", past_due_since: 2.days.ago)
      stub_subscription(cancel_at_period_end: true)

      post_event("invoice.payment_succeeded", { "customer" => "cus_123", "subscription" => "sub_123" })

      expect(student.reload.subscription_status).to eq("canceling")
    end
  end

  describe "customer.subscription.updated" do
    it "marca past_due quando o Stripe diz past_due" do
      post_event("customer.subscription.updated",
                 { "id" => "sub_123", "status" => "past_due", "cancel_at_period_end" => false,
                   "current_period_end" => 1.month.from_now.to_i })

      student.reload
      expect(student.subscription_status).to eq("past_due")
      expect(student.past_due_since).to be_present
    end

    it "marca past_due quando o Stripe diz unpaid" do
      post_event("customer.subscription.updated",
                 { "id" => "sub_123", "status" => "unpaid", "cancel_at_period_end" => false,
                   "current_period_end" => 1.month.from_now.to_i })

      expect(student.reload.subscription_status).to eq("past_due")
    end

    it "NÃO apaga uma tolerância em curso quando o Stripe ainda diz past_due" do
      primeira_falha = 3.days.ago
      student.update!(subscription_status: "past_due", past_due_since: primeira_falha)

      post_event("customer.subscription.updated",
                 { "id" => "sub_123", "status" => "past_due", "cancel_at_period_end" => false,
                   "current_period_end" => 1.month.from_now.to_i })

      # Era exatamente este o bug: o handler assumia "active" sempre que não
      # houvesse cancelamento agendado, então qualquer subscription.updated
      # devolvia acesso a quem estava com o cartão recusado.
      expect(student.reload.subscription_status).to eq("past_due")
      expect(student.reload.past_due_since).to be_within(1.second).of(primeira_falha)
    end

    it "volta pra ativo quando o Stripe diz active" do
      student.update!(subscription_status: "past_due", past_due_since: 3.days.ago)

      post_event("customer.subscription.updated",
                 { "id" => "sub_123", "status" => "active", "cancel_at_period_end" => false,
                   "current_period_end" => 1.month.from_now.to_i })

      student.reload
      expect(student.subscription_status).to eq("active")
      expect(student.past_due_since).to be_nil
    end

    it "marca canceling quando há cancelamento agendado" do
      post_event("customer.subscription.updated",
                 { "id" => "sub_123", "status" => "active", "cancel_at_period_end" => true,
                   "current_period_end" => 5.days.from_now.to_i })

      expect(student.reload.subscription_status).to eq("canceling")
    end
  end

  describe "customer.subscription.deleted" do
    it "rebaixa pra trial e encerra a assinatura" do
      student.update!(subscription_status: "past_due", past_due_since: 10.days.ago, level: "B1")

      post_event("customer.subscription.deleted", { "id" => "sub_123" })

      expect(response).to have_http_status(:ok)
      student.reload
      expect(student.role).to eq("trial")
      expect(student.subscription_status).to eq("canceled")
    end

    it "rebaixa mesmo o aluno que não tem nível" do
      # Defesa em profundidade. Hoje o model exige nível de todo aluno, então
      # este estado não deveria existir — mas um handler de webhook não pode
      # falhar por causa de dado torto: se o `update!` explodisse, o Stripe
      # receberia 500, tentaria de novo, falharia igual, e o aluno ficaria com
      # acesso de pagante indefinidamente, sem pagar.
      # O update_columns grava sem validar, simulando o dado ruim.
      student.update_columns(level: nil)

      post_event("customer.subscription.deleted", { "id" => "sub_123" })

      expect(response).to have_http_status(:ok)
      expect(student.reload.role).to eq("trial")
    end
  end

  describe "checkout.session.completed" do
    # Quem acabou de pagar veio da landing: entrou como trial e nunca criou senha.
    let!(:pagante) { create(:user, :trial, email: "pagou@exemplo.fr", language: "fr") }

    def checkout_completed(user)
      stub_subscription
      post_event("checkout.session.completed", {
        "customer"     => "cus_novo",
        "subscription" => "sub_novo",
        "metadata"     => { "user_id" => user.id.to_s }
      })
    end

    it "ativa a assinatura" do
      checkout_completed(pagante)

      expect(response).to have_http_status(:ok)
      pagante.reload
      expect(pagante.role).to eq("student")
      expect(pagante.subscription_status).to eq("active")
    end

    it "manda as boas-vindas na língua do cadastro" do
      perform_enqueued_jobs { checkout_completed(pagante) }

      email = ActionMailer::Base.deliveries.find { |m| m.to == ["pagou@exemplo.fr"] }
      expect(email.subject).to include("Bienvenue")
      expect(email.body.encoded).to include("Votre accès complet est ouvert")
    end

    it "carrega o link de criar senha pra quem ainda não tem uma" do
      perform_enqueued_jobs { checkout_completed(pagante) }

      email = ActionMailer::Base.deliveries.last
      expect(email.body.encoded).to include("reset_password_token")
      expect(pagante.reload.reset_password_token).to be_present
    end

    it "não manda link de senha pra quem já criou a sua" do
      com_senha = create(:user, :trial, email: "temsenha@exemplo.fr", password_set_at: 1.day.ago)

      perform_enqueued_jobs { checkout_completed(com_senha) }

      email = ActionMailer::Base.deliveries.find { |m| m.to == ["temsenha@exemplo.fr"] }
      expect(email.body.encoded).not_to include("reset_password_token")
    end

    it "gerar o token não conta como escolher senha" do
      checkout_completed(pagante)

      # Se contasse, a pessoa perderia o formulário da tela de sucesso e o prazo
      # longo do link — justo ela, que continua sem senha nenhuma.
      expect(pagante.reload.passwordless?).to be true
    end
  end

  # deliver_later enfileira no GoodJob; em teste o adapter é :test, então os jobs
  # ficam em ActiveJob::Base.queue_adapter.enqueued_jobs.
  def enqueued_mailer_count
    ActiveJob::Base.queue_adapter.enqueued_jobs.count { |j| j["job_class"] == "ActionMailer::MailDeliveryJob" || j[:job] == ActionMailer::MailDeliveryJob }
  end
end
