require 'rails_helper'

# O agente de conteúdo parou de gerar em julho de 2026 e ninguém soube por quê:
# as metas tinham sido atingidas, ele dizia isso num flash, e nenhum flash deste
# app chegava à tela. Estes testes cobrem a decisão do agente — qual nível ele
# escolhe, e quando se recusa a escolher.
#
# O caso que importa mais é "gera num nível SEM meta definida": no código antigo
# a lista de níveis válidos vinha da constante TARGET, então o C1 (que existe no
# enum, na avaliação de nivelamento e no formulário da landing) era impossível
# de gerar por qualquer caminho. Este teste falha no código antigo.
RSpec.describe "Admin::Drafts metas", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin) { create(:user, :admin) }
  let!(:teacher) do
    create(:user, :teacher, email: Admin::DraftsController::TEACHER_EMAIL)
  end

  before { sign_in admin }

  def set_goal(level, goal)
    ContentTarget.find_or_initialize_by(level: level).update!(goal: goal)
  end

  def stock(level, count, draft: false)
    count.times do |i|
      create(:activity,
             title:        "#{level} atividade #{i} #{SecureRandom.hex(4)}",
             level:        level,
             teacher:      teacher,
             ai_generated: true,
             draft:        draft)
    end
  end

  def requested_level
    AiGeneration.last.request_params["level"]
  end

  describe "modo automático" do
    it "escolhe o nível mais distante da própria meta" do
      set_goal("A1", 10)
      set_goal("B1", 10)
      stock("A1", 8)  # faltam 2
      stock("B1", 3)  # faltam 7

      post admin_generate_draft_path, params: { level: "" }

      expect(requested_level).to eq("B1")
      expect(AiActivityGenerationJob).to have_been_enqueued
    end

    it "conta rascunhos junto das publicadas" do
      set_goal("A1", 10)
      set_goal("B1", 10)
      stock("A1", 2)
      stock("A1", 6, draft: true) # 8 no total, faltam 2
      stock("B1", 3)              # faltam 7

      post admin_generate_draft_path, params: { level: "" }

      expect(requested_level).to eq("B1")
    end

    it "ignora nível sem meta definida" do
      set_goal("A1", 10)
      stock("A1", 9)      # falta 1
      set_goal("C1", nil) # sem meta, e sem nenhuma atividade

      post admin_generate_draft_path, params: { level: "" }

      expect(requested_level).to eq("A1")
    end

    it "avisa quando todas as metas foram atingidas, sem enfileirar nada" do
      set_goal("A1", 2)
      stock("A1", 2)

      expect {
        post admin_generate_draft_path, params: { level: "" }
      }.not_to change(AiGeneration, :count)

      expect(response).to redirect_to(admin_drafts_path)
      expect(flash[:notice]).to match(/Meta atingida/)
      expect(AiActivityGenerationJob).not_to have_been_enqueued
    end

    it "avisa quando nenhum nível tem meta" do
      post admin_generate_draft_path, params: { level: "" }

      expect(flash[:notice]).to match(/Meta atingida/)
    end
  end

  describe "nível escolhido na mão" do
    it "gera num nível SEM meta definida" do
      set_goal("C1", nil)
      set_goal("A1", 30) # o automático escolheria A1

      post admin_generate_draft_path, params: { level: "C1" }

      expect(requested_level).to eq("C1")
      expect(AiActivityGenerationJob).to have_been_enqueued
    end

    it "gera mesmo com a meta daquele nível já batida" do
      set_goal("B2", 2)
      stock("B2", 5)

      post admin_generate_draft_path, params: { level: "B2" }

      expect(requested_level).to eq("B2")
    end

    it "cai no automático quando o nível não existe no enum" do
      set_goal("A2", 10)

      post admin_generate_draft_path, params: { level: "Z9" }

      expect(requested_level).to eq("A2")
    end
  end

  describe "PATCH /admin/drafts/targets" do
    it "salva as metas enviadas" do
      patch admin_draft_targets_path, params: { goals: { "A1" => "12", "B2" => "7" } }

      expect(ContentTarget.goals["A1"]).to eq(12)
      expect(ContentTarget.goals["B2"]).to eq(7)
      expect(flash[:notice]).to eq("Metas atualizadas.")
    end

    it "meta em branco apaga a meta, e o nível sai do automático" do
      set_goal("A1", 10)

      patch admin_draft_targets_path, params: { goals: { "A1" => "" } }

      expect(ContentTarget.goals["A1"]).to be_nil

      post admin_generate_draft_path, params: { level: "" }
      expect(flash[:notice]).to match(/Meta atingida/)
    end

    it "recusa meta inválida sem gravar nada" do
      set_goal("B1", 10)

      patch admin_draft_targets_path, params: { goals: { "B1" => "-3" } }

      expect(ContentTarget.goals["B1"]).to eq(10)
      expect(flash[:alert]).to match(/Meta inválida/)
    end

    it "ignora nível que não existe no enum" do
      patch admin_draft_targets_path, params: { goals: { "Z9" => "5" } }

      expect(ContentTarget.find_by(level: "Z9")).to be_nil
    end
  end

  # A tela desenha três situações diferentes por nível (com meta batida, com
  # meta faltando, e sem meta) mais o rodapé do total. O rodapé divide pelo
  # total das metas, então "nenhum nível tem meta" é uma divisão por zero
  # esperando acontecer — por isso ele tem teste próprio.
  describe "GET /admin/drafts" do
    it "renderiza com metas batidas, faltando e ausentes na mesma tela" do
      set_goal("A1", 2)
      stock("A1", 5)  # batida
      set_goal("B1", 10)
      stock("B1", 3)  # faltando
      set_goal("C1", nil) # sem meta

      get admin_drafts_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("sem meta")
      expect(response.body).to include("faltam 7")
    end

    it "renderiza quando nenhum nível tem meta" do
      get admin_drafts_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Nenhum nível tem meta definida")
    end

    it "oferece os cinco níveis do enum na lista de geração" do
      get admin_drafts_path

      Activity.levels.keys.each do |level|
        expect(response.body).to include(">#{level}</option>")
      end
    end
  end

  describe "ContentTarget.goals" do
    it "devolve todos os níveis do enum, com nil onde não há meta" do
      set_goal("A1", 30)

      expect(ContentTarget.goals.keys).to eq(Activity.levels.keys)
      expect(ContentTarget.goals["A1"]).to eq(30)
      expect(ContentTarget.goals["C1"]).to be_nil
    end
  end
end
