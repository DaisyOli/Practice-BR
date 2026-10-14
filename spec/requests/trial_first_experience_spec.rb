require 'rails_helper'

# O que a pessoa do teste vê dentro da plataforma: quanto teste ainda tem, e o
# próximo passo assim que termina uma atividade.
RSpec.describe "Primeira experiência no teste", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:trial) { create(:user, :trial, level: "B1", trial_expires_at: Time.zone.parse("2030-03-21 10:00")) }
  let!(:primeira) { create(:activity, :B1, draft: false, title: "No mercado") }
  let!(:segunda)  { create(:activity, :B1, draft: false, title: "Na farmácia") }

  before { sign_in trial }

  describe "dashboard" do
    it "diz quantas atividades o teste tem e até quando vale" do
      get student_dashboard_path

      expect(response.body).to include("Seu teste gratuito")
      expect(response.body).to include("0 de 3")
      expect(response.body).to include("21/03")
    end

    it "não aparece para aluno pagante" do
      sign_in create(:user, :student)
      get student_dashboard_path

      expect(response.body).not_to include("Seu teste gratuito")
    end

    it "registra o primeiro acesso, uma vez só" do
      get student_dashboard_path
      primeiro = trial.reload.first_access_at

      get student_dashboard_path
      expect(trial.reload.first_access_at).to eq(primeiro)
    end
  end

  describe "fim da primeira atividade" do
    before do
      create(:question, :multiple_choice, activity: primeira)
      post submit_activity_path(primeira), params: { answers: { primeira.questions.first.id.to_s => "Brasília" } }
      follow_redirect!
    end

    it "comemora e manda ver o resultado — a próxima fica no fim dele" do
      expect(response.body).to include("Primeira atividade feita!")
      expect(response.body).to include("a próxima atividade está esperando")
      expect(response.body).not_to include(solve_activity_path(segunda))
    end

    it "o resultado detalhado oferece a próxima atividade, entre tentar de novo e voltar ao painel" do
      get results_activity_path(primeira)

      corpo = response.body
      expect(corpo).to include("Próxima atividade")
      expect(corpo).to include("Na farmácia")
      tentar = corpo.index(I18n.t("quiz.try_again"))
      proxima = corpo.index("Próxima atividade 🌱")
      painel = corpo.index("Voltar ao Meu Painel")
      expect(tentar).to be < proxima
      expect(proxima).to be < painel
    end
  end

  describe "próxima atividade para aluno pagante" do
    let(:aluno) { create(:user, :student, level: "B1") }

    before do
      sign_in aluno
      create(:question, :multiple_choice, activity: primeira)
      post submit_activity_path(primeira), params: { answers: { primeira.questions.first.id.to_s => "Brasília" } }
    end

    it "aparece também fora do teste, passando pela avaliação" do
      get results_activity_path(primeira)

      expect(response.body).to include("Próxima atividade")
      expect(response.body).to include("goAfterRating")
    end

    it "some quando o limite diário foi atingido — o clique daria numa porta fechada" do
      allow_any_instance_of(User).to receive(:daily_limit_reached?).and_return(true)
      get results_activity_path(primeira)

      expect(response.body).not_to include("Próxima atividade")
    end
  end

  describe "expressões escritas" do
    it "liga o passo do tour só quando já existe uma corrigida" do
      get student_dashboard_path
      expect(response.body).to include('data-has-written="false"')

      aberta = create(:activity, :B1, draft: false)
      create(:question, :open_ended, activity: aberta)
      create(:quiz_attempt, user: trial, activity: aberta)

      get student_dashboard_path
      expect(response.body).to include('data-has-written="true"')
    end
  end

  describe "fim da terceira atividade (bug achado em 14/10/2026)" do
    let!(:terceira) { create(:activity, :B1, draft: false, title: "No correio") }

    before do
      [primeira, segunda].each { |a| create(:quiz_attempt, user: trial, activity: a) }
      trial.update_column(:trial_activities_used, 2)
      create(:question, :multiple_choice, activity: terceira)
      post submit_activity_path(terceira), params: { answers: { terceira.questions.first.id.to_s => "Brasília" } }
    end

    it "mostra a nota antes de falar em fim de teste" do
      follow_redirect!

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Você fez as 3 atividades do teste!")
      expect(response.body).to include(trial_expired_path)
      expect(response.body).not_to include("Primeira atividade feita!")
    end

    it "o resultado detalhado não oferece tentar de novo nem próxima — leva ao que vem depois" do
      get results_activity_path(terceira)

      expect(response.body).to include("Continuar praticando")
      expect(response.body).not_to include("Próxima atividade 🌱")
    end

    it "deixa abrir o resultado detalhado" do
      get results_activity_path(terceira)
      expect(response).to have_http_status(:ok)
    end

    it "não deixa responder de novo nem abrir atividade nova" do
      get solve_activity_path(terceira)
      expect(response).to redirect_to(trial_expired_path)

      outra = create(:activity, :B1, draft: false)
      get solve_activity_path(outra, show_score: "true")
      expect(response).to redirect_to(trial_expired_path)
    end
  end
end
