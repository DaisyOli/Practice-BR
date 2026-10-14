require 'rails_helper'

# A Vitrine do teste: a Daisy escolhe, por nível, as atividades que quem chega
# encontra primeiro.
RSpec.describe "Vitrine do teste", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin)    { create(:user, :admin) }
  let!(:recente) { create(:activity, :B1, draft: false, title: "A mais recente", created_at: 1.hour.ago) }
  let!(:curta)   { create(:activity, :B1, draft: false, title: "A curta e bonita", created_at: 1.month.ago) }
  let!(:aberta)  { create(:activity, :B1, draft: false, title: "A da IA", created_at: 2.months.ago) }

  def salvar(b1)
    patch admin_showcase_path, params: { showcase: { "B1" => b1 } }
  end

  describe "o painel" do
    before { sign_in admin }

    it "mostra os níveis e o que o teste usa hoje sem vitrine" do
      get admin_showcase_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Vitrine do teste")
      expect(CGI.unescapeHTML(response.body)).to include("hoje o teste mostra \"A mais recente\"")
    end

    it "grava a ordem escolhida" do
      salvar("1" => curta.id, "2" => aberta.id)

      expect(curta.reload.trial_showcase_position).to eq(1)
      expect(aberta.reload.trial_showcase_position).to eq(2)
      expect(recente.reload.trial_showcase_position).to be_nil
    end

    it "troca posições sem esbarrar no índice único" do
      salvar("1" => curta.id, "2" => aberta.id)
      salvar("1" => aberta.id, "2" => curta.id)

      expect(aberta.reload.trial_showcase_position).to eq(1)
      expect(curta.reload.trial_showcase_position).to eq(2)
    end

    it "ignora atividade repetida e de outro nível" do
      outra = create(:activity, :A2, draft: false)
      salvar("1" => curta.id, "2" => curta.id, "3" => outra.id)

      expect(curta.reload.trial_showcase_position).to eq(1)
      expect(outra.reload.trial_showcase_position).to be_nil
    end

    it "não abre para quem não é admin" do
      sign_in create(:user, :teacher)
      get admin_showcase_path

      expect(response).to redirect_to(root_path)
    end
  end

  describe "o que quem chega pelo teste encontra" do
    let(:trial) { create(:user, :trial, level: "B1") }

    before do
      curta.update_column(:trial_showcase_position, 1)
      aberta.update_column(:trial_showcase_position, 2)
    end

    it "começa pela 1ª da vitrine, não pela mais recente" do
      expect(trial.suggested_first_activity).to eq(curta)
    end

    it "segue a ordem depois da primeira" do
      create(:quiz_attempt, user: trial, activity: curta)
      expect(trial.suggested_first_activity).to eq(aberta)
    end

    it "cai na mais recente quando a vitrine acabou" do
      [curta, aberta].each { |a| create(:quiz_attempt, user: trial, activity: a) }
      expect(trial.suggested_first_activity).to eq(recente)
    end

    it "pula a que voltou a ser rascunho" do
      curta.update_column(:draft, true)
      expect(trial.suggested_first_activity).to eq(aberta)
    end

    it "a próxima no fim do resultado segue a vitrine" do
      sign_in trial
      create(:question, :multiple_choice, activity: curta)
      post submit_activity_path(curta), params: { answers: { curta.questions.first.id.to_s => "Brasília" } }

      get results_activity_path(curta)
      expect(response.body).to include("A da IA")
    end

    it "atividade que muda de nível sai da vitrine" do
      curta.update!(level: "B2")
      expect(curta.reload.trial_showcase_position).to be_nil
    end
  end
end
