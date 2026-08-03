require 'rails_helper'

# O bloco "Comece por aqui" da dashboard do aluno.
#
# Por que existe: quem chega e nunca praticou encontra ~148 atividades em 4
# níveis. É o mesmo problema que o lembrete semanal tinha (teto de 5, 03/08/2026)
# — lista longa não convida, intimida. Aqui a resposta é mais forte que um teto:
# uma escolha só.
#
# Decisão de escopo registrada: isto entrou por DESIGN, não por métrica. Os 4
# trials com zero atividades que motivaram a investigação tinham outra causa (a
# barreira da caixa de entrada, corrigida em 6e78c68), então não há dado provando
# que este bloco move ativação. Não esperar que um número o valide depois.
RSpec.describe "Comece por aqui", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:trial) { create(:user, :trial, level: "B1") }

  before { sign_in trial }

  context "quem nunca praticou" do
    it "vê o convite com uma atividade escolhida" do
      atividade = create(:activity, :B1, draft: false, title: "Pedir comida por aplicativo")

      get student_dashboard_path

      expect(response.body).to include("Comece por aqui")
      expect(response.body).to include("Pedir comida por aplicativo")
      expect(response.body).to include(solve_activity_path(atividade))
    end

    it "recebe UMA, não a lista inteira" do
      create_list(:activity, 9, :B1, draft: false)

      get student_dashboard_path

      # O convite aponta para um só destino. Se algum dia o bloco virar lista,
      # este número sobe e o teste avisa.
      expect(response.body.scan(/Começar →/).size).to eq(1)
    end

    it "oferece a MESMA que o email de ativação ofereceria" do
      create_list(:activity, 5, :B1, draft: false)

      # Se as duas escolhas divergissem, o email mandaria para uma atividade e a
      # tela ofereceria outra — incoerência invisível até alguém receber as duas.
      do_email = TrialSequenceJob.new.send(:first_activity_for, trial)

      get student_dashboard_path

      expect(response.body).to include(solve_activity_path(do_email))
    end

    it "não aparece se não houver atividade no nível da pessoa" do
      create(:activity, :A1, draft: false)

      get student_dashboard_path

      # Convite para uma tela vazia é pior que silêncio — mesma regra dos jobs.
      expect(response.body).not_to include("Comece por aqui")
    end

    it "não aparece para quem ainda não tem nível" do
      trial.update_columns(level: nil)
      create(:activity, :B1, draft: false)

      get student_dashboard_path

      expect(response.body).not_to include("Comece por aqui")
    end
  end

  context "quem já praticou" do
    it "não vê mais o convite — some sozinho, sem flag nem coluna" do
      atividade = create(:activity, :B1, draft: false)
      create(:quiz_attempt, user: trial, activity: atividade)

      get student_dashboard_path

      expect(response.body).not_to include("Comece por aqui")
    end

    it "vale mesmo para quem abriu e não terminou" do
      feita = create(:activity, :B1, draft: false)
      create(:quiz_attempt, user: trial, activity: feita, submitted_at: nil)
      create(:activity, :B1, draft: false)

      # Quem abriu uma atividade já encontrou o caminho: o convite virou ruído,
      # mesmo que não tenha enviado as respostas.
      get student_dashboard_path

      expect(response.body).not_to include("Comece por aqui")
    end
  end

  describe "User#suggested_first_activity" do
    it "não repete o que a pessoa já fez" do
      feita = create(:activity, :B1, draft: false, created_at: 1.hour.ago)
      nova  = create(:activity, :B1, draft: false, created_at: 2.hours.ago)
      create(:quiz_attempt, user: trial, activity: feita)

      expect(trial.suggested_first_activity).to eq(nova)
    end

    it "não oferece rascunho" do
      create(:activity, :B1, draft: true)

      expect(trial.suggested_first_activity).to be_nil
    end

    it "fica só no nível declarado, que é o único que o teste abre" do
      create(:activity, :A1, draft: false)

      expect(trial.suggested_first_activity).to be_nil
    end
  end
end
