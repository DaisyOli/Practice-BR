require 'rails_helper'

# Fase B: depois do teste, a dashboard fica aberta para consulta, com a faixa
# de fim no topo; e o email do fim virou um balanço pessoal.
RSpec.describe "Depois do teste", type: :request do
  include Devise::Test::IntegrationHelpers

  let!(:feita) { create(:activity, :B1, draft: false, title: "No mercado") }
  let!(:nova)  { create(:activity, :B1, draft: false, title: "Na farmácia") }
  let(:pessoa) { create(:user, :trial, level: "B1", trial_activities_used: 3, trial_expires_at: 3.days.from_now) }

  before do
    create(:quiz_attempt, user: pessoa, activity: feita, score: 85)
    sign_in pessoa
  end

  describe "a dashboard" do
    it "continua aberta, com a faixa de fim e a melhor nota" do
      get student_dashboard_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Seu teste terminou")
      expect(response.body).to include("sua melhor nota foi 85%")
      expect(response.body).to include(billing_new_path)
      expect(response.body).not_to include("Comece por aqui")
    end

    it "vale para quem deixou o prazo vencer" do
      pessoa.update_columns(trial_activities_used: 1, trial_expires_at: 1.day.ago)
      get student_dashboard_path

      expect(response.body).to include("Seu teste terminou")
    end

    it "atividade nova continua levando à tela de fim" do
      get solve_activity_path(nova)
      expect(response).to redirect_to(trial_expired_path)
    end

    it "convidado por professora continua indo para a assinatura" do
      pessoa.update_column(:invitation_accepted_at, 1.day.ago)
      get student_dashboard_path
      expect(response).to redirect_to(billing_new_path)
    end

    it "durante o teste não mostra a faixa de fim" do
      pessoa.update_column(:trial_activities_used, 1)
      get student_dashboard_path
      expect(response.body).not_to include("Seu teste terminou")
    end
  end

  describe "o email do fim" do
    it "é um balanço: as atividades com nota, e um trecho da correção da IA" do
      aberta = create(:activity, :B1, draft: false, title: "Minha cidade")
      create(:quiz_attempt, user: pessoa, activity: aberta, score: 70, results: {
        "score" => 70, "total_questions" => 1,
        "results" => {
          "8" => { "question_type" => "open_ended", "ai_score" => 0,  "ai_feedback" => "Não respondida" },
          "9" => { "question_type" => "open_ended", "ai_score" => 80, "ai_feedback" => "Muito bom o uso do pretérito!" }
        }
      })

      corpo = CGI.unescapeHTML(TrialMailer.ended_email(pessoa.reload, 120).body.encoded)

      expect(corpo).to include("No mercado")
      expect(corpo).to include("85%")
      expect(corpo).to include("Muito bom o uso do pretérito!")
      expect(corpo).to include("Ver meus resultados")
      expect(corpo).not_to include("Não respondida")
    end

    it "não mostra nota abaixo da aprovação — mostra que foi feita" do
      fraca = create(:activity, :B1, draft: false, title: "Difícil")
      create(:quiz_attempt, user: pessoa, activity: fraca, score: 10)

      corpo = CGI.unescapeHTML(TrialMailer.ended_email(pessoa.reload, 120).body.encoded)
      expect(corpo).not_to include("10%")
      expect(corpo).to include("✓")
    end

    it "o da próxima atividade diz o título e quantas a assinatura abre" do
      corpo = CGI.unescapeHTML(TrialMailer.next_step_email(pessoa, nova).body.encoded)

      expect(corpo).to include("Na farmácia")
      expect(corpo).to include("Ver os planos")
    end
  end
end
