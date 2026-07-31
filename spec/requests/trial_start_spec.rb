require 'rails_helper'

# O caminho que a landing usa: cadastro → dentro do app, sem passar pela caixa
# de entrada. Os testes aqui cobrem os dois lados — que a pessoa certa entra, e
# que o link não vira atalho de login pra mais ninguém.
RSpec.describe "Entrada do trial pela landing", type: :request do
  include ActiveSupport::Testing::TimeHelpers
  include Devise::Test::IntegrationHelpers

  describe "POST /api/v1/trials" do
    it "devolve o start_url junto com o ok" do
      post "/api/v1/trials", params: { email: "novo@email.com", level: "B1" }, as: :json

      body = JSON.parse(response.body)
      expect(body["ok"]).to be true
      expect(body["start_url"]).to be_present
      expect(body["start_url"]).to include("/comecar?token=")
    end

    it "continua mandando o email — ele virou o caminho de volta, não sumiu" do
      expect {
        perform_enqueued_jobs do
          post "/api/v1/trials", params: { email: "novo@email.com", level: "B1" }, as: :json
        end
      }.to change { ActionMailer::Base.deliveries.count }.by(2) # boas-vindas + aviso interno
    end
  end

  describe "GET /comecar" do
    let(:user) { create(:user, :trial, language: "fr") }
    let(:token) { TrialStartToken.generate(user) }

    it "entra com a pessoa e leva pra dashboard" do
      get trial_start_path(token: token)

      expect(response).to redirect_to(student_dashboard_path)
      follow_redirect!
      expect(response).to have_http_status(:ok)
    end

    it "dá as boas-vindas no idioma da pessoa" do
      get trial_start_path(token: token)
      expect(flash[:notice]).to include("Bienvenue")
    end

    it "entrar não gasta nada do trial" do
      get trial_start_path(token: token)

      user.reload
      expect(user.trial_activities_used).to eq(0)
      expect(user.trial_start_used_at).to be_present
    end

    context "segurança do link" do
      it "vale uma vez só" do
        get trial_start_path(token: token)
        expect(response).to redirect_to(student_dashboard_path)

        reset!  # novo navegador, sem sessão
        get trial_start_path(token: token)
        expect(response).to redirect_to(new_user_session_path)
      end

      it "expira em 30 minutos" do
        link = trial_start_path(token: token)

        travel(31.minutes) do
          get link
          expect(response).to redirect_to(new_user_session_path)
        end
      end

      it "não serve para quem já virou aluna pagante" do
        link = trial_start_path(token: token)
        user.update!(role: "student")

        get link
        expect(response).to redirect_to(new_user_session_path)
      end

      it "não engole token inventado" do
        get trial_start_path(token: "isto-nao-e-um-token")
        expect(response).to redirect_to(new_user_session_path)
      end

      it "não deixa sessão nenhuma pra trás quando o token é inválido" do
        get trial_start_path(token: "invalido")

        # A prova de que ninguém entrou: a dashboard continua fechada.
        get student_dashboard_path
        expect(response).to redirect_to(new_user_session_path)
      end
    end

    context "quando a pessoa já está dentro" do
      # Link clicado duas vezes, aba recarregada, prefetch do navegador: mostrar
      # erro pra quem já está logada seria confuso à toa.
      it "não mostra erro, só leva pra dashboard" do
        get trial_start_path(token: token)
        get trial_start_path(token: token)

        expect(response).to redirect_to(student_dashboard_path)
        expect(flash[:alert]).to be_blank
      end
    end
  end
end
