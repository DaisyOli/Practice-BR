require 'rails_helper'

# Os sinais de que há uma pessoa usando o teste. Separam gente do robô de email,
# que pede as páginas mas não toca em nada.
RSpec.describe "Sinais do teste", type: :request do
  include Devise::Test::IntegrationHelpers

  let!(:atividade) { create(:activity, :A1, draft: false) }
  let(:pessoa) { create(:user, :trial, level: "A1") }

  describe "POST /sinal-do-teste" do
    before { sign_in pessoa }

    {
      "app" => :first_human_at, "activity" => :first_activity_human_at, "answer" => :first_answer_at
    }.each do |kind, column|
      it "grava #{column} para o sinal #{kind}" do
        post trial_signal_path, params: { kind: kind }, as: :json

        expect(response).to have_http_status(:no_content)
        expect(pessoa.reload.public_send(column)).to be_present
      end
    end

    it "guarda só a primeira vez" do
      primeira = 2.days.ago.change(usec: 0)
      pessoa.update_column(:first_human_at, primeira)

      post trial_signal_path, params: { kind: "app" }, as: :json

      expect(pessoa.reload.first_human_at).to eq(primeira)
    end

    it "ignora sinal desconhecido, sem deixar escolher a coluna" do
      post trial_signal_path, params: { kind: "admin" }, as: :json

      expect(response).to have_http_status(:no_content)
      expect(pessoa.reload.admin).to be_falsey
    end

    it "funciona com o teste encerrado: a dashboard continua aberta" do
      pessoa.update_columns(trial_activities_used: 3)

      post trial_signal_path, params: { kind: "app" }, as: :json

      expect(response).to have_http_status(:no_content)
      expect(pessoa.reload.first_human_at).to be_present
    end
  end

  it "não grava nada para quem não está no teste" do
    aluno = create(:user, :student)
    sign_in aluno

    post trial_signal_path, params: { kind: "app" }, as: :json

    expect(aluno.reload.first_human_at).to be_nil
  end

  it "exige login" do
    post trial_signal_path, params: { kind: "app" }, as: :json

    expect(pessoa.reload.first_human_at).to be_nil
  end

  describe "a página" do
    before { sign_in pessoa }

    it "liga o sinal enquanto falta algum, e desliga quando estão todos gravados" do
      get student_dashboard_path
      expect(response.body).to include('data-controller="trial-signal"')

      pessoa.update_columns(first_human_at: Time.current, first_activity_human_at: Time.current,
                            first_answer_at: Time.current)
      get student_dashboard_path
      expect(response.body).not_to include('data-controller="trial-signal"')
    end

    it "não aparece para aluno pagante" do
      sign_in create(:user, :student)
      get student_dashboard_path

      expect(response.body).not_to include('data-controller="trial-signal"')
    end
  end

  describe "por onde entrou" do
    it "registra a landing na primeira entrada" do
      get trial_start_path(token: TrialStartToken.generate(pessoa))

      expect(pessoa.reload.first_entry_source).to eq("landing")
    end

    it "registra o email quando a primeira entrada é pelo botão dele" do
      get trial_link_path(token: TrialEmailLink.generate(pessoa, to: "dashboard"))

      expect(pessoa.reload.first_entry_source).to eq("email")
    end

    it "não troca: quem entrou pela landing e volta pelo email continua sendo landing" do
      get trial_start_path(token: TrialStartToken.generate(pessoa))
      get trial_link_path(token: TrialEmailLink.generate(pessoa, to: "dashboard"))

      expect(pessoa.reload.first_entry_source).to eq("landing")
    end

    it "conta antiga que volta não ganha origem" do
      pessoa.update_column(:first_access_at, 3.days.ago)
      get trial_link_path(token: TrialEmailLink.generate(pessoa, to: "dashboard"))

      expect(pessoa.reload.first_entry_source).to be_nil
    end

    it "o robô que segue o link do email não vira gente" do
      get trial_link_path(token: TrialEmailLink.generate(pessoa, to: "activity", activity: atividade))
      follow_redirect!

      pessoa.reload
      expect(pessoa.first_activity_opened_at).to be_present
      expect(pessoa.first_human_at).to be_nil
      expect(pessoa.first_activity_human_at).to be_nil
    end
  end
end
