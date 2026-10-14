require 'rails_helper'

# As ferramentas novas da Sugestão do Dia: o programa do nível, o catálogo
# inteiro e os erros reais dos alunos.
RSpec.describe DailySuggestionAgentService do
  let(:teacher) { create(:user, :teacher) }
  let(:agent)   { described_class.new(teacher: teacher) }

  before { allow(Anthropic::Client).to receive(:new).and_return(double) }

  def tool(name, level = "A1")
    agent.send(name, level)
  end

  describe "level_syllabus" do
    it "usa o texto de fábrica e, quando a Daisy reescreve, o dela" do
      expect(tool(:level_syllabus)).to include("ser × estar")

      AiPrompt.create!(key: "daily_suggestion.syllabus.A1", body: "Meu programa do A1: só cumprimentos.")
      expect(tool(:level_syllabus)).to eq("Meu programa do A1: só cumprimentos.")
    end

    it "tem um programa para cada nível" do
      Activity.levels.keys.each { |lvl| expect(tool(:level_syllabus, lvl)).to be_present }
    end
  end

  describe "level_catalog" do
    it "lista todas as publicadas do nível, de qualquer professora, com tema" do
      create(:activity, :A1, draft: false, title: "Na padaria", theme: "Comida", teacher: create(:user, :teacher))
      create(:activity, :A1, draft: true,  title: "Rascunho")

      result = tool(:level_catalog)
      expect(result).to include("Na padaria [Comida]")
      expect(result).not_to include("Rascunho")
    end
  end

  describe "frequent_errors" do
    let(:atividade) { create(:activity, :A1, draft: false, title: "Como você está?") }

    def tentativa(aluno, given:, ok:)
      create(:quiz_attempt, user: aluno, activity: atividade, results: {
        "score" => 0, "total_questions" => 1,
        "results" => { "1" => {
          "question_type" => "fill_in_blank", "question_text" => "Eu _____ cansado hoje.",
          "correct_answer" => "estou", "is_correct" => ok,
          "blank_results" => [{ "given" => given, "correct" => "estou", "ok" => ok }]
        } }
      })
    end

    it "mostra o que os alunos escreveram no lugar da resposta certa" do
      2.times { tentativa(create(:user, :student), given: "sou", ok: false) }
      tentativa(create(:user, :student), given: "estou", ok: true)

      result = tool(:frequent_errors)
      expect(result).to include("Eu _____ cansado hoje.")
      expect(result).to include("certa: \"estou\"")
      expect(result).to include("erraram 2 de 3")
      expect(result).to include("\"sou\" (2)")
    end

    it "não conta professoras nem as contas excluídas" do
      tentativa(create(:user, :teacher), given: "sou", ok: false)
      daisy_aluna = create(:user, :student)
      tentativa(daisy_aluna, given: "sou", ok: false)

      ENV["STATS_EXCLUDE_USER_IDS"] = daisy_aluna.id.to_s
      expect(tool(:frequent_errors)).to include("Dados insuficientes")
    ensure
      ENV.delete("STATS_EXCLUDE_USER_IDS")
    end

    it "diz quando não há dados" do
      expect(tool(:frequent_errors)).to include("Dados insuficientes")
    end
  end
end
