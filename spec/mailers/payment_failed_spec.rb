require 'rails_helper'

# Emails de falha de pagamento são disparados de dentro do webhook, via
# deliver_later. Um erro de template não apareceria na requisição — morreria no
# job. Estas specs renderizam os dois de verdade.
RSpec.describe "Emails de falha de pagamento" do
  let(:student) do
    create(:user, :student,
           name: "Camille",
           level: "B1",
           stripe_customer_id: "cus_123",
           stripe_subscription_id: "sub_123",
           subscription_status: "past_due",
           past_due_since: 2.days.ago)
  end

  describe StudentMailer, "#payment_failed" do
    it "renderiza e diz quantos dias faltam" do
      mail = described_class.payment_failed(student)

      expect(mail.to).to eq([student.email])
      expect(mail.subject).to include("pagamento")
      expect(mail.body.encoded).to include("Camille")
      expect(mail.body.encoded).to include("#{User::PAYMENT_GRACE_DAYS - 2} dias")
      expect(mail.body.encoded).to include(billing_update_payment_url)
    end

    it "usa o idioma do aluno" do
      student.update!(language: "fr")
      mail = described_class.payment_failed(student)

      expect(mail.subject).to include("Problème de paiement")
      expect(mail.body.encoded).to include("Mettre à jour le paiement")
    end

    it "cai no total da tolerância quando não há data de início" do
      student.update!(past_due_since: nil)
      mail = described_class.payment_failed(student)

      expect(mail.body.encoded).to include("#{User::PAYMENT_GRACE_DAYS} dias")
    end
  end

  describe AdminMailer, "#payment_failed_notification" do
    it "renderiza e identifica o aluno pra Daisy" do
      mail = described_class.payment_failed_notification(student)

      expect(mail.to).to eq([AdminMailer::DAISY_EMAIL])
      expect(mail.subject).to include("Falha de pagamento")
      expect(mail.body.encoded).to include("Camille")
      expect(mail.body.encoded).to include(student.email)
      expect(mail.body.encoded).to include("B1")
    end
  end
end
