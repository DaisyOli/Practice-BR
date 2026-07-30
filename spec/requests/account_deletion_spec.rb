require 'rails_helper'

# O destroy do Devise apagava a conta sem avisar o Stripe: a assinatura seguia
# viva, o cartão seguia sendo cobrado, e a pessoa não tinha mais conta pra entrar
# e cancelar. O webhook da cobrança não encontrava usuário e desistia em
# silêncio — ninguém ficava sabendo.
RSpec.describe "Exclusão de conta", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:aluno_pagante) do
    create(:user, :student,
           stripe_customer_id: "cus_123",
           stripe_subscription_id: "sub_123",
           subscription_status: "active")
  end

  describe "aluno pagante" do
    before { sign_in aluno_pagante }

    it "cancela a assinatura no Stripe e só então apaga a conta" do
      expect(Stripe::Subscription).to receive(:cancel).with("sub_123").ordered
      allow(AdminMailer).to receive(:account_deleted_notification).and_call_original

      expect { delete "/users" }.to change(User, :count).by(-1)

      expect(User.exists?(aluno_pagante.id)).to be(false)
    end

    it "cancela imediatamente, não no fim do período" do
      # `cancel_at_period_end` deixaria, num plano anual, uma assinatura "ativa"
      # no Stripe por meses pra alguém que não existe mais.
      expect(Stripe::Subscription).to receive(:cancel).with("sub_123")
      expect(Stripe::Subscription).not_to receive(:update)

      delete "/users"
    end

    it "enfileira o aviso pra admin" do
      allow(Stripe::Subscription).to receive(:cancel)

      # O conteúdo do email (e o fato de não levar dado pessoal) é testado em
      # spec/mailers/account_deleted_spec.rb.
      delete "/users"

      expect(enqueued_admin_mail).to be_present
    end

    context "quando o Stripe falha" do
      before { allow(Stripe::Subscription).to receive(:cancel).and_raise(Stripe::APIError.new("timeout")) }

      it "NÃO apaga a conta" do
        expect { delete "/users" }.not_to change(User, :count)
        expect(User.exists?(aluno_pagante.id)).to be(true)
      end

      it "explica pro aluno e manda ele de volta" do
        delete "/users"

        expect(response).to redirect_to(student_dashboard_path)
        expect(flash[:alert]).to include("não apagamos sua conta")
      end
    end
  end

  describe "aluno sem assinatura" do
    let(:trial) { create(:user, :trial) }

    it "apaga sem falar com o Stripe" do
      sign_in trial
      expect(Stripe::Subscription).not_to receive(:cancel)

      expect { delete "/users" }.to change(User, :count).by(-1)
    end
  end

  describe "professora" do
    let(:professora) { create(:user, :teacher) }

    it "não consegue se auto-excluir" do
      sign_in professora

      expect { delete "/users" }.not_to change(User, :count)
      expect(response).to redirect_to(teacher_dashboard_path)
      expect(flash[:alert]).to include("Contas de professora não são apagadas por aqui")
    end

    it "não perde as atividades por causa disso" do
      # O has_many :activities tem dependent: :destroy. Se a professora
      # conseguisse se apagar, levaria embora as atividades que os alunos usam.
      create(:activity, teacher: professora, draft: false)
      sign_in professora

      expect { delete "/users" }.not_to change(Activity, :count)
    end

    it "é mandada pra tela de contato ao tentar abrir a página de exclusão" do
      sign_in professora
      get account_deletion_path

      expect(response).to redirect_to(teacher_dashboard_path)
    end
  end

  describe "tela de confirmação" do
    it "avisa o aluno pagante que a assinatura é cancelada sem devolução" do
      sign_in aluno_pagante
      get account_deletion_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("assinatura é cancelada na hora")
      expect(response.body).to include("não é devolvido")
    end

    it "oferece cancelar só a assinatura, pra quem só quer parar de pagar" do
      sign_in aluno_pagante
      get account_deletion_path

      expect(response.body).to include("cancelar apenas a assinatura")
    end

    it "não fala de assinatura pra quem não tem" do
      sign_in create(:user, :trial)
      get account_deletion_path

      expect(response.body).not_to include("assinatura é cancelada na hora")
    end

    it "exige login" do
      get account_deletion_path
      expect(response).to redirect_to(new_user_session_path)
    end
  end

  def enqueued_admin_mail
    ActiveJob::Base.queue_adapter.enqueued_jobs.find do |job|
      job[:args].to_s.include?("account_deleted_notification")
    end
  end
end
