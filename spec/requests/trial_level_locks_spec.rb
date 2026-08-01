require 'rails_helper'

# O bug que apareceu no teste em produção de 2026-08-01: a dashboard oferecia
# uma atividade A2 pra uma conta de teste B1, e a própria plataforma recusava
# abrir meio segundo depois. Duas intenções que se atropelavam — a dashboard
# sorteia níveis mais fáceis de propósito, e a porta do trial só aceita o nível
# declarado.
#
# A escolha foi mostrar cadeado em vez de esconder: quem está no teste vê o que
# a assinatura devolve, e o cadeado leva pra tela de assinatura.
RSpec.describe "Cadeados de nível durante o teste", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:aluno_teste) { create(:user, :trial, level: "B1") }
  let!(:do_nivel)   { create(:activity, :B1, draft: false) }
  let!(:mais_facil) { create(:activity, :A2, draft: false) }

  before { sign_in aluno_teste }

  describe "dashboard" do
    it "não oferece atividade que a própria plataforma vai recusar" do
      get student_dashboard_path

      # O link de resolver só pode existir para a atividade do nível declarado.
      expect(response.body).to include(solve_activity_path(do_nivel))
      expect(response.body).not_to include(solve_activity_path(mais_facil))
    end

    it "põe cadeado com caminho pra assinatura nos níveis que a assinatura devolve" do
      get student_dashboard_path

      expect(response.body).to include("com a assinatura")
      expect(response.body).to include(billing_new_path)
    end

    it "troca o botão de resolver por cadeado ao abrir um nível mais fácil" do
      # A lista por nível (?level=A2) é onde os cards aparecem de verdade.
      get student_dashboard_path(level: "A2")

      expect(response.body).to include("Com a assinatura")
      expect(response.body).not_to include(solve_activity_path(mais_facil))
    end

    it "sugere em 'Continue estudando' só o que abre" do
      # Antes o sorteio ponderado podia pôr A1/A2 na frente, e o card mais
      # visível da dashboard virava uma porta fechada.
      10.times { expect(aluno_teste.weighted_priority_levels).to eq(["B1"]) }
    end
  end

  describe "catálogo" do
    it "troca o 'Ver' por cadeado nas atividades de outro nível" do
      get activities_path

      expect(response.body).not_to include(activity_path(mais_facil))
      expect(response.body).to include("Com a assinatura")
    end
  end

  describe "aluno pagante" do
    it "continua vendo os níveis anteriores sem cadeado — é o que ele comprou" do
      sign_in create(:user, :student, level: "B1")

      get student_dashboard_path(level: "A2")

      expect(response.body).to include(solve_activity_path(mais_facil))
      expect(response.body).not_to include("Com a assinatura")
    end
  end

  describe "a porta continua trancada" do
    it "quem chega pela URL direta segue barrado" do
      # O cadeado é a cara amigável da regra; a regra em si não pode depender
      # de ninguém clicar no lugar certo.
      get solve_activity_path(mais_facil)

      expect(response).to redirect_to(student_dashboard_path)
    end
  end
end
