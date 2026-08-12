require 'rails_helper'

RSpec.describe "Admin::AiPrompts", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin)   { create(:user, :admin) }
  let(:teacher) { create(:user, :teacher) }

  # Chave com pontos — é ela que exige a constraint na rota. Se a rota voltar a
  # ler o ".A1" como formato, este teste é o que cai.
  let(:key) { "ai_grading.expectations.A1" }

  describe "quem pode entrar" do
    it "barra professora que não é admin" do
      sign_in teacher
      get admin_ai_prompts_path

      expect(response).to redirect_to(root_path)
    end

    it "barra visitante" do
      get admin_ai_prompts_path

      expect(response).to have_http_status(:redirect)
    end
  end

  context "como admin" do
    before { sign_in admin }

    describe "GET index" do
      it "lista as nove vozes e a IA sem prompt" do
        get admin_ai_prompts_path

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Régua do A1")
        expect(response.body).to include("Instruções principais")
        expect(response.body).to include("Whisper")
      end

      it "marca como reescrito só o que foi reescrito" do
        AiPrompt.create!(key: key, body: "Régua minha do A1.")

        get admin_ai_prompts_path

        expect(response.body).to include("reescrito")
      end

      # Uma linha salva com o texto IGUAL ao do código não é uma reescrita —
      # marcar como "reescrito" faria você procurar uma diferença que não existe.
      it "não marca como reescrito quando o texto salvo é igual ao do código" do
        AiPrompt.create!(key: key, body: AiGradingService::LEVEL_EXPECTATIONS["A1"])

        get admin_ai_prompts_path

        expect(response.body).not_to include("reescrito")
      end
    end

    describe "GET edit" do
      it "abre com o texto do código quando nunca foi reescrito" do
        get edit_admin_ai_prompt_path(key)

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("SEJA MUITO GENEROSO")
      end

      it "recusa chave que não existe" do
        get edit_admin_ai_prompt_path("nao.existe")

        expect(response).to redirect_to(admin_ai_prompts_path)
      end

      # A tela com histórico só é DESENHADA quando existe versão antiga. Sem
      # este teste, um erro na formatação da data ficaria escondido: o spec de
      # restaurar só olha o redirecionamento, nunca renderiza a página.
      # O prompt de geração tem 282 linhas, aspas e chaves de JSON, e o texto
      # original vai inteiro para dentro de um atributo HTML (o editor compara
      # com ele ao vivo). É o caso mais provável de quebrar a página.
      it "abre o prompt gigante da geração com os marcadores à mostra" do
        get edit_admin_ai_prompt_path("activity_generation.system")

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("SCHEMA DO JSON")
        expect(response.body).to include("exercises")
      end

      it "desenha o histórico com data e tamanho" do
        prompt = AiPrompt.create!(key: key, body: "Primeira régua.")
        prompt.update!(body: "Segunda régua.")

        get edit_admin_ai_prompt_path(key)

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Versões anteriores")
        expect(response.body).to include("#{'Primeira régua.'.length} caracteres")
      end

      it "oferece voltar ao original só quando o texto foi reescrito" do
        get edit_admin_ai_prompt_path(key)
        expect(response.body).not_to include("Voltar ao original")

        AiPrompt.create!(key: key, body: "Régua minha.")
        get edit_admin_ai_prompt_path(key)

        expect(response.body).to include("Voltar ao original")
      end
    end

    describe "PATCH update" do
      it "salva e passa a valer na correção seguinte" do
        patch admin_ai_prompt_path(key), params: { ai_prompt: { body: "Régua nova do A1." } }

        expect(response).to redirect_to(admin_ai_prompts_path)
        expect(AiPrompt.body_for(key)).to eq("Régua nova do A1.")
      end

      it "recusa texto que quebra o contrato e DEVOLVE o que ela escreveu" do
        rascunho = "Corrija com carinho e devolva a nota."

        patch admin_ai_prompt_path("ai_grading.system"), params: { ai_prompt: { body: rascunho } }

        expect(response).to have_http_status(:unprocessable_entity)
        # Perder uma reescrita longa por erro de validação seria cruel.
        expect(response.body).to include(rascunho)
        expect(AiPrompt.find_by(key: "ai_grading.system")).to be_nil
      end
    end

    describe "DELETE destroy" do
      it "volta ao texto do código" do
        AiPrompt.create!(key: key, body: "Régua reescrita.")

        delete admin_ai_prompt_path(key)

        expect(AiPrompt.find_by(key: key)).to be_nil
        expect(AiPrompt.body_for(key)).to eq(AiGradingService::LEVEL_EXPECTATIONS["A1"])
      end
    end

    describe "POST restore" do
      it "traz de volta uma versão anterior" do
        prompt = AiPrompt.create!(key: key, body: "Primeira.")
        prompt.update!(body: "Segunda.")
        versao = prompt.versions.first

        post restore_admin_ai_prompt_path(key, version_id: versao.id)

        expect(prompt.reload.body).to eq("Primeira.")
        # A que estava valendo virou histórico, e nada se perdeu.
        expect(prompt.versions.map(&:body)).to include("Segunda.")
      end
    end
  end
end
