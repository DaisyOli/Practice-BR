# O rótulo do link de exclusão precisa avisar da assinatura ANTES do clique.
#
# Apagar a conta cancela a assinatura na hora e não devolve o período já pago
# (AccountDeletionService). Um link que diz só "excluir minha conta" faz a pessoa
# descobrir isso na tela seguinte — depois de já ter decidido.
#
# O que não pode acontecer, nas duas direções: prometer cancelamento a quem não
# tem assinatura (trial, aluno gratuito) é inventar contrato; esconder o
# cancelamento de quem tem é o problema original.
require 'rails_helper'

RSpec.describe "Rótulo da exclusão de conta", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:student) { create(:user, :student) }

  describe "na dashboard" do
    it "avisa da assinatura para quem tem uma ativa" do
      student.update!(stripe_subscription_id: "sub_123", subscription_status: "active")
      sign_in student

      get student_dashboard_path

      expect(response.body).to include("Cancelar assinatura e excluir conta")
      expect(response.body).to include("Résilier mon abonnement et supprimer mon compte")
    end

    it "não inventa assinatura para quem não tem" do
      sign_in student

      get student_dashboard_path

      expect(response.body).to include("Excluir minha conta")
      expect(response.body).not_to include("Cancelar assinatura e excluir conta")
      expect(response.body).not_to include("Résilier mon abonnement et supprimer mon compte")
    end

    it "não fala em cancelar o que já está cancelado" do
      student.update!(stripe_subscription_id: "sub_123", subscription_status: "canceled")
      sign_in student

      get student_dashboard_path

      expect(response.body).not_to include("Cancelar assinatura e excluir conta")
    end
  end

  # O botão de cancelar assinatura responde à mesma pergunta que o rótulo, e
  # errava nela: o `stripe_subscription_id` continua gravado depois que a
  # assinatura encerra, então ele oferecia cancelar o que já tinha acabado.
  #
  # As asserções miram a classe do botão, não o texto: o texto também vive no
  # bloco de traduções em JS, que precisa existir sempre que houver QUALQUER
  # coisa pra traduzir — inclusive a mensagem de data do estado `canceling`.
  describe "botão de cancelar assinatura" do
    it "aparece para assinatura ativa" do
      student.update!(stripe_subscription_id: "sub_123", subscription_status: "active")
      sign_in student

      get student_dashboard_path

      expect(response.body).to include(%(class="cancel-sub-btn"))
    end

    it "não oferece cancelar assinatura que já acabou" do
      student.update!(stripe_subscription_id: "sub_123", subscription_status: "canceled")
      sign_in student

      get student_dashboard_path

      expect(response.body).not_to include(%(class="cancel-sub-btn"))
    end

    # `canceling` é cancelamento agendado: já pediu, ainda tem acesso até o fim
    # do período. Mostra a data, não o botão de novo.
    it "mostra a data de fim em vez do botão para quem já cancelou" do
      student.update!(stripe_subscription_id: "sub_123",
                      subscription_status: "canceling",
                      subscription_current_period_end: Date.new(2026, 9, 15))
      sign_in student

      get student_dashboard_path

      expect(response.body).not_to include(%(class="cancel-sub-btn"))
      expect(response.body).to include("15/09/2026")
    end

    it "não aparece para quem nunca assinou" do
      sign_in student

      get student_dashboard_path

      expect(response.body).not_to include(%(class="cancel-sub-btn"))
      expect(response.body).not_to include("Cancelar inscrição")
    end
  end

  # O rótulo e a tela têm que concordar: se um diz que a assinatura morre e o
  # outro não, a pessoa clica achando uma coisa e lê outra.
  describe "concordância entre o rótulo e a tela de confirmação" do
    it "os dois enxergam a mesma assinatura" do
      student.update!(stripe_subscription_id: "sub_123", subscription_status: "active")
      sign_in student

      get account_deletion_path

      expect(response.body).to include("résilié immédiatement")
      expect(student.stripe_subscription_open?).to be(true)
    end

    # `incomplete` não dá acesso, mas é assinatura viva na Stripe — e o destroy
    # vai cancelá-la. Por isso a pergunta é mais larga que `subscription_ongoing?`.
    it "conta assinatura em estado que não dá acesso, porque o destroy cancela ela também" do
      student.update!(stripe_subscription_id: "sub_123", subscription_status: "incomplete")

      expect(student.subscription_ongoing?).to be(false)
      expect(student.stripe_subscription_open?).to be(true)
    end
  end
end
