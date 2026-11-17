require 'rails_helper'

# Arquivar (ponto 1.5, 17/11/2026): no lugar de excluir, que apaga o histórico.
# No piloto de 17/11 as originais foram excluídas depois de virarem pílulas.
RSpec.describe "Arquivar atividade", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin)    { create(:user, :admin) }
  let(:student)  { create(:user, :student, level: "B1") }
  let(:original) { create(:activity, :B1, teacher: admin, draft: false, title: "A longa original") }

  describe "a dona da atividade" do
    before { sign_in admin }

    it "arquiva e desarquiva" do
      post archive_activity_path(original)
      expect(response).to redirect_to(activity_path(original))
      expect(original.reload).to be_archived

      get activity_path(original)
      expect(response.body).to include("Arquivada em", "Desarquivar")

      post unarchive_activity_path(original)
      expect(original.reload).not_to be_archived
    end

    it "na original que já virou pílulas, a página sugere arquivar" do
      create(:activity, :B1, teacher: admin, draft: false, pill: true, source_activity: original,
                             series_key: "s", series_position: 1)

      get activity_path(original)
      expect(response.body).to include("já virou", "1 pílula publicada", "Arquivar a original")
    end

    it "o aviso de excluir diz quantas tentativas se perdem" do
      get activity_path(original)
      expect(response.body).to include("Nenhum aluno fez ainda")

      create_list(:quiz_attempt, 2, activity: original)
      get activity_path(original)
      expect(response.body).to include("2 tentativas de alunos", "use Arquivar")
    end

    it "as arquivadas saem da lista e ficam no filtro" do
      original.archive!

      get activities_path
      expect(response.body).not_to include("A longa original")

      get activities_path(arquivadas: "1")
      expect(response.body).to include("A longa original", "📦 Arquivada")
    end
  end

  it "outra professora não arquiva atividade alheia" do
    sign_in create(:user, :teacher)
    post archive_activity_path(original)

    expect(response).to redirect_to(activities_path)
    expect(original.reload).not_to be_archived
  end

  describe "o aluno, com a atividade arquivada" do
    before do
      original.archive!
      sign_in student
    end

    it "um link antigo leva às pílulas, se ela virou pílulas" do
      pilula = create(:activity, :B1, teacher: admin, draft: false, pill: true, source_activity: original,
                                      series_key: "s", series_position: 1)
      get solve_activity_path(original)

      expect(response).to redirect_to(solve_activity_path(pilula))
      expect(flash[:notice]).to include("versão mais curta")
    end

    it "senão, volta para o painel" do
      get solve_activity_path(original)
      expect(response).to redirect_to(student_dashboard_path)
    end

    # Sem tentativa anterior: um envio que passasse criaria uma (o envio de quem
    # já tem tentativa só atualiza a dela, e a contagem não mudaria).
    it "não envia mais respostas" do
      expect { post submit_activity_path(original), params: { answers: {} } }.not_to change(QuizAttempt, :count)
      expect(response).to redirect_to(student_dashboard_path)
    end

    it "o resultado antigo continua abrindo" do
      create(:quiz_attempt, user: student, activity: original)

      get results_activity_path(original)
      expect(response).to have_http_status(:ok)
    end
  end
end
