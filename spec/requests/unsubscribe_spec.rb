require 'rails_helper'

# Descadastro dos emails não transacionais. Os dois lados: quem pede para sair
# sai de verdade (em todo caminho de envio), e o que é sobre a conta continua
# chegando.
RSpec.describe "Descadastro", type: :request do
  include ActiveJob::TestHelper

  let!(:atividade) { create(:activity, :B1, draft: false) }
  let(:pessoa) { create(:user, :trial, level: "B1", language: "fr") }
  let(:token)  { UnsubscribeToken.generate(pessoa) }

  describe "a página" do
    it "o link só pergunta — abrir não descadastra (antivírus abre tudo)" do
      get unsubscribe_path(token: token)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Ne plus recevoir nos emails ?")
      expect(pessoa.reload.marketing_emails_opted_out?).to be false
    end

    it "o botão descadastra" do
      post unsubscribe_path(token: token)

      expect(pessoa.reload.marketing_emails_opted_out?).to be true
      expect(CGI.unescapeHTML(response.body)).to include("C'est noté")
    end

    it "aceita o clique único do Gmail, sem token CSRF" do
      ActionController::Base.allow_forgery_protection = true
      post unsubscribe_path(token: token), params: { "List-Unsubscribe" => "One-Click" }

      expect(response).to have_http_status(:ok)
      expect(pessoa.reload.marketing_emails_opted_out?).to be true
    ensure
      ActionController::Base.allow_forgery_protection = false
    end

    it "deixa voltar atrás" do
      pessoa.update_column(:marketing_emails_opted_out_at, 1.day.ago)
      post resubscribe_path(token: token)

      expect(pessoa.reload.marketing_emails_opted_out?).to be false
    end

    it "recusa token inválido sem quebrar" do
      get unsubscribe_path(token: "lixo")
      expect(response).to have_http_status(:not_found)

      post unsubscribe_path(token: "lixo")
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "os emails" do
    it "levam o link no rodapé e o cabeçalho de clique único" do
      mail = TrialMailer.first_nudge_email(pessoa, atividade)

      expect(mail.body.encoded).to include("/descadastrar?token=")
      expect(mail["List-Unsubscribe"].to_s).to include("/descadastrar?token=")
      expect(mail["List-Unsubscribe-Post"].to_s).to eq("List-Unsubscribe=One-Click")
    end

    it "não saem para quem descadastrou — nem pela sequência automática" do
      pessoa.update_columns(marketing_emails_opted_out_at: 1.day.ago, created_at: 5.hours.ago)

      perform_enqueued_jobs { TrialSequenceJob.perform_now }

      expect(ActionMailer::Base.deliveries).to be_empty
    end

    it "nem os de aluno pagante (lembrete de inatividade)" do
      aluno = create(:user, :student, level: "B1", marketing_emails_opted_out_at: 1.day.ago)

      expect { StudentMailer.inactivity_nudge(aluno, atividade).deliver_now }
        .not_to change { ActionMailer::Base.deliveries.size }
    end

    it "os da conta continuam chegando: boas-vindas e pagamento" do
      pessoa.update_column(:marketing_emails_opted_out_at, 1.day.ago)
      aluno = create(:user, :student, level: "B1", marketing_emails_opted_out_at: 1.day.ago)

      expect {
        TrialMailer.welcome_email(pessoa).deliver_now
        StudentMailer.payment_failed(aluno).deliver_now
      }.to change { ActionMailer::Base.deliveries.size }.by(2)
    end
  end
end
