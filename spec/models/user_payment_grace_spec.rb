require 'rails_helper'

# Tolerância de pagamento: quando o cartão de um aluno é recusado, o acesso não
# cai na hora — ele tem User::PAYMENT_GRACE_DAYS pra atualizar. Estas specs
# existem porque o bug original era justamente o silêncio: o subscription_status
# era gravado e nunca lido, então cartão recusado significava acesso de graça por
# tempo indeterminado.
RSpec.describe User, type: :model do
  let(:student) do
    create(:user, :student,
           stripe_customer_id: "cus_123",
           stripe_subscription_id: "sub_123")
  end

  describe "#mark_payment_past_due!" do
    it "marca o status e registra o início da tolerância" do
      student.mark_payment_past_due!

      expect(student.subscription_status).to eq("past_due")
      expect(student.past_due_since).to be_within(5.seconds).of(Time.current)
    end

    it "NÃO reinicia a contagem em falhas seguintes" do
      first_failure = 5.days.ago
      student.update!(subscription_status: "past_due", past_due_since: first_failure)

      student.mark_payment_past_due!

      # O Stripe reenvia invoice.payment_failed a cada nova tentativa do cartão.
      # Se cada uma reiniciasse a contagem, a tolerância nunca expiraria.
      expect(student.reload.past_due_since).to be_within(1.second).of(first_failure)
    end
  end

  describe "#clear_payment_past_due!" do
    it "zera a data ao voltar pra ativo" do
      student.update!(subscription_status: "past_due", past_due_since: 3.days.ago)

      student.clear_payment_past_due!

      expect(student.subscription_status).to eq("active")
      expect(student.past_due_since).to be_nil
    end

    it "aceita um status diferente, como canceling" do
      student.update!(subscription_status: "past_due", past_due_since: 3.days.ago)

      student.clear_payment_past_due!(status: "canceling")

      expect(student.subscription_status).to eq("canceling")
      expect(student.past_due_since).to be_nil
    end
  end

  describe "#payment_grace_expired?" do
    it "é falso dentro da tolerância" do
      student.update!(subscription_status: "past_due", past_due_since: 3.days.ago)
      expect(student).not_to be_payment_grace_expired
    end

    it "é falso no último dia da tolerância" do
      student.update!(subscription_status: "past_due",
                      past_due_since: (User::PAYMENT_GRACE_DAYS - 1).days.ago)
      expect(student).not_to be_payment_grace_expired
    end

    it "é verdadeiro depois da tolerância" do
      student.update!(subscription_status: "past_due",
                      past_due_since: (User::PAYMENT_GRACE_DAYS + 1).days.ago)
      expect(student).to be_payment_grace_expired
    end

    it "é falso quando o pagamento está em dia, mesmo com data antiga sobrando" do
      student.update!(subscription_status: "active", past_due_since: 30.days.ago)
      expect(student).not_to be_payment_grace_expired
    end

    it "é falso quando não há data de início" do
      # Sem a data não há como contar a tolerância. Trancar um aluno pagante por
      # falta de dado é pior que dar acesso a mais por alguns dias.
      student.update!(subscription_status: "past_due", past_due_since: nil)
      expect(student).not_to be_payment_grace_expired
    end
  end

  describe "#payment_grace_days_left" do
    it "conta os dias restantes" do
      student.update!(subscription_status: "past_due", past_due_since: 2.days.ago)
      expect(student.payment_grace_days_left).to eq(User::PAYMENT_GRACE_DAYS - 2)
    end

    it "nunca devolve número negativo" do
      student.update!(subscription_status: "past_due", past_due_since: 30.days.ago)
      expect(student.payment_grace_days_left).to eq(0)
    end

    it "é nil quando o pagamento está em dia" do
      expect(student.payment_grace_days_left).to be_nil
    end
  end
end
