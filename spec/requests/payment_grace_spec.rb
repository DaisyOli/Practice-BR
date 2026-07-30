require 'rails_helper'

# O bug que estas specs travam: `subscription_status` era gravado pelo webhook e
# nunca lido em lugar nenhum, então um aluno com cartão recusado seguia com
# acesso completo até o Stripe desistir das tentativas — semanas de acesso de
# graça, sem ninguém saber.
RSpec.describe "Tolerância de pagamento no acesso", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:student) do
    create(:user, :student,
           stripe_customer_id: "cus_123",
           stripe_subscription_id: "sub_123",
           subscription_status: "active")
  end

  def past_due!(days_ago)
    student.update!(subscription_status: "past_due", past_due_since: days_ago.days.ago)
  end

  before { sign_in student }

  context "pagamento em dia" do
    it "acessa a dashboard normalmente" do
      get student_dashboard_path
      expect(response).to have_http_status(:ok)
    end
  end

  context "dentro da tolerância" do
    before { past_due!(2) }

    it "continua acessando a dashboard" do
      get student_dashboard_path
      expect(response).to have_http_status(:ok)
    end

    it "avisa quantos dias faltam" do
      get student_dashboard_path
      expect(response.body).to include("Seu último pagamento não passou")
      expect(response.body).to include("#{User::PAYMENT_GRACE_DAYS - 2} dias")
    end
  end

  context "tolerância vencida" do
    before { past_due!(User::PAYMENT_GRACE_DAYS + 1) }

    it "manda pra tela de pagamento pendente em vez da dashboard" do
      get student_dashboard_path
      expect(response).to redirect_to(billing_payment_problem_path)
    end

    it "bloqueia também as atividades, não só a dashboard" do
      get activities_path
      expect(response).to redirect_to(billing_payment_problem_path)
    end

    it "deixa a própria tela de pagamento pendente abrir" do
      # Sem esta exceção o bloqueio viraria um laço de redirecionamento.
      get billing_payment_problem_path
      expect(response).to have_http_status(:ok)
    end

    it "deixa o aluno sair" do
      # Este app usa `config.sign_out_via = :get` no Devise.
      get destroy_user_session_path
      expect(response).to redirect_to(root_path)
    end
  end

  context "pagamento regularizado depois da tolerância vencida" do
    it "volta a acessar tudo" do
      past_due!(User::PAYMENT_GRACE_DAYS + 1)
      student.clear_payment_past_due!

      get student_dashboard_path
      expect(response).to have_http_status(:ok)
    end
  end
end
