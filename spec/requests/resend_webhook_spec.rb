require 'rails_helper'

# Devoluções e marcações de spam avisadas pelo Resend. Este endereço decide para
# quem a plataforma para de escrever, então a assinatura é o centro dos testes.
RSpec.describe "Webhook do Resend", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:secret)   { "whsec_#{Base64.strict_encode64('segredo-de-teste-32-bytes-aaaaaa')}" }
  let(:atividade) { create(:activity, :A1, draft: false) }
  let(:pessoa)   { create(:user, :trial, level: "A1", email: "pessoa@exemplo.com") }

  around do |ex|
    ENV["RESEND_WEBHOOK_SECRET"] = secret
    ex.run
  ensure
    ENV.delete("RESEND_WEBHOOK_SECRET")
  end

  def aviso(type: "email.bounced", to: [pessoa.email], bounce_type: "Permanent", sign_with: secret, timestamp: Time.now.to_i)
    body = { type: type, data: { to: to, subject: "Assunto", bounce: { type: bounce_type, subType: "General" } } }.to_json
    id   = "msg_1"
    signature = StandardWebhooks::Webhook.new(sign_with).sign(id, timestamp, body)
    post "/webhooks/resend", params: body,
         headers: { "CONTENT_TYPE" => "application/json", "svix-id" => id,
                    "svix-timestamp" => timestamp.to_s, "svix-signature" => signature }
  end

  describe "a assinatura" do
    it "aceita um aviso assinado" do
      aviso
      expect(response).to have_http_status(:ok)
      expect(pessoa.reload.email_bounced?).to be true
    end

    it "recusa assinatura errada, sem marcar ninguém" do
      aviso(sign_with: "whsec_#{Base64.strict_encode64('outro-segredo-32-bytes-bbbbbbbbb')}")
      expect(response).to have_http_status(:bad_request)
      expect(pessoa.reload.email_bounced?).to be false
    end

    it "recusa aviso sem os cabeçalhos" do
      pessoa
      post "/webhooks/resend", params: { type: "email.bounced", data: { to: [pessoa.email] } }, as: :json
      expect(response).to have_http_status(:bad_request)
      expect(pessoa.reload.email_bounced?).to be false
    end

    it "recusa aviso antigo reenviado" do
      aviso(timestamp: 1.hour.ago.to_i)
      expect(response).to have_http_status(:bad_request)
    end

    it "sem o segredo configurado, recusa em vez de aceitar qualquer um" do
      ENV.delete("RESEND_WEBHOOK_SECRET")
      aviso
      expect(response).to have_http_status(:service_unavailable)
      expect(pessoa.reload.email_bounced?).to be false
    end
  end

  describe "os avisos" do
    # Foi assim que veio o aviso real de 03/11/2026: tipo "Transient", com a
    # resposta "550 5.7.1 ... não tem permissão para ... mensagens externas".
    # Este teste dizia o contrário (com "Temporary", o exemplo da documentação),
    # e a regra deixava passar o único caso de verdade.
    it "devolução \"Transient\" também marca" do
      aviso(bounce_type: "Transient")
      expect(pessoa.reload.email_bounced?).to be true
    end

    it "marcar como spam vale como pedido para sair" do
      aviso(type: "email.complained")
      expect(pessoa.reload.marketing_emails_opted_out?).to be true
      expect(pessoa.email_bounced?).to be false
    end

    it "ignora maiúsculas no endereço e endereço desconhecido" do
      pessoa
      aviso(to: ["PESSOA@exemplo.com", "ninguem@exemplo.com"])
      expect(response).to have_http_status(:ok)
      expect(pessoa.reload.email_bounced?).to be true
    end

    it "aviso repetido mantém a primeira data" do
      primeira = 2.days.ago.change(usec: 0)
      pessoa.update_column(:email_bounced_at, primeira)
      aviso
      expect(pessoa.reload.email_bounced_at).to eq(primeira)
    end

    it "evento desconhecido só responde ok" do
      aviso(type: "email.delivered")
      expect(response).to have_http_status(:ok)
      expect(pessoa.reload.email_bounced?).to be false
    end
  end

  describe "depois da devolução" do
    before { pessoa.update_column(:email_bounced_at, 1.hour.ago) }

    it "os lembretes não saem" do
      expect { TrialMailer.first_nudge_email(pessoa, atividade).deliver_now }
        .not_to change { ActionMailer::Base.deliveries.size }
    end

    it "os emails da conta continuam: pode ser a chance de corrigir o endereço" do
      expect { TrialMailer.welcome_email(pessoa).deliver_now }
        .to change { ActionMailer::Base.deliveries.size }.by(1)
    end

    it "o botão de lembrete não aparece, e o painel avisa" do
      pessoa.update_column(:trial_activities_used, 1)
      sign_in create(:user, :admin)
      get admin_root_path

      expect(response.body).to include("email devolvido")
      expect(response.body).not_to include(admin_send_trial_reminder_path(pessoa))
    end

    it "a recuperação não escolhe essa conta" do
      pessoa.update_column(:created_at, Time.zone.parse("2026-10-12 10:00"))
      linha = TrialRecovery.new(from: "2026-10-12", to: "2026-10-12").report.find { |r| r.user == pessoa }
      expect(linha.reason).to eq("o endereço de email devolve")
    end

    it "trocar de email apaga a marca" do
      pessoa.update!(email: "novo@exemplo.com")
      expect(pessoa.reload.email_bounced?).to be false
    end
  end

  it "destinatário e assunto do aviso não aparecem nos logs" do
    filtro = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
    limpo  = filtro.filter("to" => ["a@b.com"], "subject" => "Novo trial: a@b.com", "total_questions" => 5)

    expect(limpo["to"]).to eq("[FILTERED]")
    expect(limpo["subject"]).to eq("[FILTERED]")
    expect(limpo["total_questions"]).to eq(5)
  end

  # O aviso real de 03/11 mostrou o que mais ia para o log: o link de
  # descadastro e a resposta do servidor da pessoa.
  it "link de descadastro e resposta do servidor também não aparecem nos logs" do
    filtro = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
    limpo  = filtro.filter("data" => {
      "headers" => [{ "name" => "List-Unsubscribe", "value" => "<https://app.practicebr.com/descadastrar?token=abc>" }],
      "bounce"  => { "type" => "Transient", "diagnosticCode" => ["smtp; 550 5.1.1 <a@b.com>: Recipient address rejected"] }
    })

    expect(limpo["data"]["headers"]).to eq("[FILTERED]")
    expect(limpo["data"]["bounce"]["diagnosticCode"]).to eq("[FILTERED]")
    expect(limpo["data"]["bounce"]["type"]).to eq("Transient")
  end
end
