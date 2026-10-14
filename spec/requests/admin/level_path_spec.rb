require 'rails_helper'

# O percurso do nível: a Daisy escolhe, por nível, até 10 atividades em ordem.
# As 3 primeiras são a vitrine do teste.
RSpec.describe "Percurso por nível", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin)    { create(:user, :admin) }
  let!(:recente) { create(:activity, :B1, draft: false, title: "A mais recente", created_at: 1.hour.ago) }
  let!(:curta)   { create(:activity, :B1, draft: false, title: "A curta e bonita", created_at: 1.month.ago) }
  let!(:aberta)  { create(:activity, :B1, draft: false, title: "A da IA", created_at: 2.months.ago) }

  def salvar(b1)
    patch admin_path_path, params: { path: { "B1" => b1 } }
  end

  describe "o painel" do
    before { sign_in admin }

    it "mostra os níveis e o que o teste usa hoje sem percurso" do
      get admin_path_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Percurso por nível")
      expect(CGI.unescapeHTML(response.body)).to include("hoje o teste mostra \"A mais recente\"")
    end

    it "grava a ordem escolhida" do
      salvar("1" => curta.id, "2" => aberta.id)

      expect(curta.reload.path_position).to eq(1)
      expect(aberta.reload.path_position).to eq(2)
      expect(recente.reload.path_position).to be_nil
    end

    it "troca posições sem esbarrar no índice único" do
      salvar("1" => curta.id, "2" => aberta.id)
      salvar("1" => aberta.id, "2" => curta.id)

      expect(aberta.reload.path_position).to eq(1)
      expect(curta.reload.path_position).to eq(2)
    end

    it "ignora atividade repetida e de outro nível" do
      outra = create(:activity, :A2, draft: false)
      salvar("1" => curta.id, "2" => curta.id, "3" => outra.id)

      expect(curta.reload.path_position).to eq(1)
      expect(outra.reload.path_position).to be_nil
    end

    it "não abre para quem não é admin" do
      sign_in create(:user, :teacher)
      get admin_path_path

      expect(response).to redirect_to(root_path)
    end
  end

  describe "o que quem chega pelo teste encontra" do
    let(:trial) { create(:user, :trial, level: "B1") }

    before do
      curta.update_column(:path_position, 1)
      aberta.update_column(:path_position, 2)
    end

    it "começa pela 1ª do percurso, não pela mais recente" do
      expect(trial.suggested_first_activity).to eq(curta)
    end

    it "segue a ordem depois da primeira" do
      create(:quiz_attempt, user: trial, activity: curta)
      expect(trial.suggested_first_activity).to eq(aberta)
    end

    it "cai na mais recente quando o percurso acabou" do
      [curta, aberta].each { |a| create(:quiz_attempt, user: trial, activity: a) }
      expect(trial.suggested_first_activity).to eq(recente)
    end

    it "pula a que voltou a ser rascunho" do
      curta.update_column(:draft, true)
      expect(trial.suggested_first_activity).to eq(aberta)
    end

    it "a próxima no fim do resultado segue o percurso" do
      sign_in trial
      create(:question, :multiple_choice, activity: curta)
      post submit_activity_path(curta), params: { answers: { curta.questions.first.id.to_s => "Brasília" } }

      get results_activity_path(curta)
      expect(response.body).to include("A da IA")
    end

    it "atividade que muda de nível sai do percurso" do
      curta.update!(level: "B2")
      expect(curta.reload.path_position).to be_nil
    end
  end

  describe "aluno pagante" do
    let(:aluno) { create(:user, :student, level: "B1") }

    before do
      curta.update_column(:path_position, 1)
      aberta.update_column(:path_position, 4)
    end

    it "também segue o percurso, além das 3 do teste" do
      create(:quiz_attempt, user: aluno, activity: curta)
      expect(aluno.next_path_activity).to eq(aberta)
    end

    it "quem já fez muitas só pula o que fez" do
      [recente, aberta].each { |a| create(:quiz_attempt, user: aluno, activity: a) }
      expect(aluno.next_path_activity).to eq(curta)
    end

    it "o cartão de próxima atividade e o 'Continue estudando' seguem o percurso" do
      sign_in aluno
      create(:question, :multiple_choice, activity: recente)
      post submit_activity_path(recente), params: { answers: { recente.questions.first.id.to_s => "Brasília" } }

      get results_activity_path(recente)
      expect(response.body).to include("A curta e bonita")
    end

    it "terminado o percurso, não há próxima de percurso — volta a sugestão automática" do
      [curta, aberta].each { |a| create(:quiz_attempt, user: aluno, activity: a) }
      expect(aluno.next_path_activity).to be_nil
    end
  end

  it "o endereço antigo da vitrine leva ao percurso" do
    sign_in admin
    get "/admin/vitrine"
    expect(response).to redirect_to("/admin/percurso")
  end

  it "aceita 10 posições e marca as 3 primeiras como teste" do
    sign_in admin
    extras = create_list(:activity, 8, :B1, draft: false)
    escolha = ([curta, aberta] + extras).each_with_index.to_h { |a, i| [(i + 1).to_s, a.id] }
    salvar(escolha)

    expect(extras.last.reload.path_position).to eq(10)
    get admin_path_path
    expect(response.body.scan("🌱 teste").size).to eq(Activity::TRIAL_SLOTS * User::CEFR_LEVELS.size)
  end
end
