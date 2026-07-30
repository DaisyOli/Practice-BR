require 'rails_helper'

# Os avisos de exclusão de conta não levam dado pessoal de propósito: a conta
# acabou de ser apagada a pedido do titular, e guardar o email dele numa caixa de
# entrada contradiz a exclusão. Estas specs travam essa decisão — é fácil alguém
# "melhorar" o email adicionando o nome do aluno e desfazer isso sem perceber.
RSpec.describe AdminMailer, "avisos de exclusão de conta" do
  let(:email_do_aluno) { "camille.dupont@exemplo.fr" }

  describe "#account_deleted_notification" do
    subject(:mail) do
      described_class.account_deleted_notification(
        user_id: 42, role: "student", stripe_customer_id: "cus_abc123"
      )
    end

    it "vai pra Daisy e identifica o usuário por id" do
      expect(mail.to).to eq([AdminMailer::DAISY_EMAIL])
      expect(mail.subject).to include("#42")
      expect(mail.body.encoded).to include("42")
    end

    it "traz o id de cliente do Stripe pra reconciliação" do
      expect(mail.body.encoded).to include("cus_abc123")
    end

    it "NÃO contém email nem nome do aluno" do
      expect(mail.body.encoded).not_to include(email_do_aluno)
      expect(mail.body.encoded).not_to include("Camille")
    end

    it "diz quando a pessoa não era pagante" do
      sem_stripe = described_class.account_deleted_notification(
        user_id: 7, role: "trial", stripe_customer_id: nil
      )

      expect(sem_stripe.body.encoded).to include("não era pagante")
    end
  end

  describe "#account_deletion_failed_notification" do
    subject(:mail) { described_class.account_deletion_failed_notification(42, "timeout na API") }

    it "deixa claro que a conta NÃO foi apagada" do
      expect(mail.subject).to include("abortada")
      expect(mail.body.encoded).to include("NÃO foi")
    end

    it "mostra o erro do Stripe e o que fazer" do
      expect(mail.body.encoded).to include("timeout na API")
      expect(mail.body.encoded).to include("Cancelar a assinatura")
    end
  end
end
