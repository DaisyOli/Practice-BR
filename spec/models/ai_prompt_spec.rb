require 'rails_helper'

# Estes testes cobrem o que pode dar errado quando um texto que o app depende
# passa a ser editável por uma pessoa — não o caminho feliz de salvar e ler.
RSpec.describe AiPrompt do
  describe "o chão" do
    # O teste que mais importa do arquivo. Se ele falhar, existe um estado em
    # que o app fica sem prompt, e "sem prompt" é uma IA que não sabe o que faz.
    it "devolve o texto do código quando não há nenhuma linha na tabela" do
      expect(described_class.count).to eq(0)

      AiPrompt.keys.each do |key|
        expect(AiPrompt.body_for(key)).to be_present,
          "a chave #{key} ficou sem texto com a tabela vazia"
      end
    end

    it "volta ao texto do código quando a linha é apagada" do
      prompt = AiPrompt.create!(key: "daily_suggestion.system",
                                body: "Instruções novas, com propose_suggestion no fim.")
      expect(AiPrompt.body_for("daily_suggestion.system")).to include("Instruções novas")

      prompt.destroy

      expect(AiPrompt.body_for("daily_suggestion.system"))
        .to eq(DailySuggestionAgentService::SYSTEM_PROMPT)
    end

    it "ignora linha com corpo em branco e cai no código" do
      # `update_column` pula as validações de propósito: o teste quer garantir
      # que mesmo um registro corrompido por fora não deixa a IA muda.
      prompt = AiPrompt.create!(key: "daily_suggestion.system", body: "propose_suggestion")
      prompt.update_column(:body, "")

      expect(AiPrompt.body_for("daily_suggestion.system"))
        .to eq(DailySuggestionAgentService::SYSTEM_PROMPT)
    end
  end

  describe "substituição dos buracos" do
    # A razão de existir do {{}} em vez de format/%{}. Este teste falha com
    # `format`: o "70%" do texto padrão levanta ArgumentError.
    it "não quebra com o '%' que existe no texto da correção" do
      expect(AiGradingService::SYSTEM_FRAME).to include("70%")

      resultado = nil
      expect {
        resultado = AiPrompt.render("ai_grading.system", expectations: "Régua do teste.")
      }.not_to raise_error

      expect(resultado).to include("70%")
      expect(resultado).to include("Régua do teste.")
      expect(resultado).not_to include("{{expectations}}")
    end

    it "deixa intacto um buraco que ninguém preencheu" do
      texto = AiPrompt.render("activity_generation.region_addendum", pedido: "Pedir café")

      expect(texto).to include("Pedir café")
      expect(texto).to include("{{regiao}}")
    end
  end

  describe "o contrato de máquina" do
    it "recusa prompt de correção sem o formato do JSON" do
      prompt = AiPrompt.new(key: "ai_grading.system",
                            body: "Avalie a resposta. {{expectations}}")

      expect(prompt).not_to be_valid
      expect(prompt.errors[:body].to_sentence).to include("score")
    end

    it "recusa prompt de correção sem o lugar da régua do nível" do
      prompt = AiPrompt.new(key: "ai_grading.system",
                            body: 'Avalie. Responda {"score": 1, "feedback": "x"}')

      expect(prompt).not_to be_valid
      expect(prompt.errors[:body].to_sentence).to include("{{expectations}}")
    end

    it "recusa instruções do agente sem a ferramenta que ele precisa chamar" do
      prompt = AiPrompt.new(key: "daily_suggestion.system", body: "Escolha um tema bacana.")

      expect(prompt).not_to be_valid
      expect(prompt.errors[:body].to_sentence).to include("propose_suggestion")
    end

    it "recusa prompt de geração sem as chaves que o parser lê" do
      prompt = AiPrompt.new(key: "activity_generation.system", body: "Crie uma atividade legal.")

      expect(prompt).not_to be_valid
      expect(prompt.errors[:body].to_sentence).to include("title")
    end

    it "aceita reescrita livre desde que os marcadores fiquem" do
      prompt = AiPrompt.new(
        key:  "ai_grading.system",
        body: <<~TXT
          Você corrige com carinho.
          {{expectations}}
          Devolva {"score": 0-100, "feedback": "texto"}
        TXT
      )

      expect(prompt).to be_valid
    end

    # A régua do nível é texto livre: nenhuma palavra dela é lida por código.
    it "não exige marcador nenhum na régua de um nível" do
      prompt = AiPrompt.new(key: "ai_grading.expectations.A1", body: "Seja generosa.")

      expect(prompt).to be_valid
    end
  end

  describe "histórico" do
    let(:prompt) do
      AiPrompt.create!(key: "ai_grading.expectations.A1", body: "Primeira régua.")
    end

    it "arquiva o texto anterior, não o novo" do
      prompt.update!(body: "Segunda régua.")

      expect(prompt.versions.count).to eq(1)
      expect(prompt.versions.first.body).to eq("Primeira régua.")
      expect(prompt.reload.body).to eq("Segunda régua.")
    end

    it "não cria versão quando nada mudou no texto" do
      prompt.update!(body: "Primeira régua.")

      expect(prompt.versions.count).to eq(0)
    end

    it "guarda uma versão por reescrita, da mais nova para a mais velha" do
      prompt.update!(body: "Segunda régua.")
      prompt.update!(body: "Terceira régua.")

      expect(prompt.versions.map(&:body)).to eq(["Segunda régua.", "Primeira régua."])
    end
  end

  describe "níveis" do
    it "tem uma régua para cada nível do enum do Activity" do
      Activity.levels.keys.each do |level|
        expect(AiPrompt.keys).to include("ai_grading.expectations.#{level}"),
          "faltou régua para o nível #{level}"
      end
    end
  end
end
